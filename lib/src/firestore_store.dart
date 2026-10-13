import 'dart:convert';
import 'dart:io';

import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:google_cloud_storage/google_cloud_storage.dart' as gcs;
import 'package:path/path.dart' as p;

import 'store.dart';
import 'tree.dart';

/// A tree kept in Firestore, with its photos in Cloud Storage. This is the
/// live record in production.
///
/// ```
/// trees/{tree}                 name, version
///   members/{email}            role, name
///   people/{id}                structured fields, body, directory
///   unions/{id}
///   media/{key}                what each file says about itself
/// ```
class FirestoreStore extends TreeStore {
  FirestoreStore(this.app, this.treeId, {required this.bucketName, required this.cacheDir});

  final FirebaseApp app;
  final String treeId;
  final String bucketName;

  /// Local scratch space for originals fetched from storage. Safe to delete.
  final String cacheDir;

  late final Firestore _db = app.firestore();
  late final DocumentReference<Map<String, Object?>> _tree =
      _db.collection('trees').doc(treeId);

  @override
  bool get requiresSignIn => true;

  @override
  Future<int> version() async =>
      ((await _tree.get()).data()?['version'] as int?) ?? 0;

  @override
  Future<Member?> member(String email) async {
    final snapshot = await _tree.collection('members').doc(email.toLowerCase()).get();
    final data = snapshot.data();
    if (data == null) return null;
    return Member(email.toLowerCase(), Role.values.byName(data['role'] as String),
        name: data['name'] as String?);
  }

  @override
  Future<Tree> load() async {
    final root = (await _tree.get()).data();
    if (root == null) throw StateError('There is no tree named "$treeId" in the database.');
    final tree = Tree(root['name'] as String? ?? treeId);

    final results = await Future.wait([
      _tree.collection('people').get(),
      _tree.collection('unions').get(),
      _tree.collection('media').get(),
    ]);
    void each(QuerySnapshot<Map<String, Object?>> docs, void Function(Map<String, Object?>) use) {
      for (final doc in docs.docs) {
        try {
          use(doc.data());
        } catch (e) {
          tree.problems.add('${doc.ref.path}: $e');
        }
      }
    }

    each(results[0], (data) {
      final fields = {...data}
        ..remove('body')
        ..remove('directory');
      final person = Person.fromMap(
          fields, data['body'] as String? ?? '', data['directory'] as String? ?? data['id'] as String);
      tree.people[person.id] = person;
    });
    each(results[1], (data) {
      final union = Union.fromMap(data);
      tree.unions[union.id] = union;
    });
    each(results[2], (data) {
      final media = Media.fromMap(data);
      tree.media[media.key] = media;
    });
    return tree;
  }

  @override
  Future<File> localFile(Media media) async {
    final file = File(p.join(cacheDir, 'originals', media.fileName));
    if (!file.existsSync()) {
      final bytes = await app.storage().bucket(bucketName).storage.downloadObject(bucketName, media.location);
      file.parent.createSync(recursive: true);
      // Write then rename, so a half-written file is never read.
      File('${file.path}.tmp')
        ..writeAsBytesSync(bytes)
        ..renameSync(file.path);
    }
    return file;
  }

  // ----------------------------------------------------------------- writes

  /// Replaces the tree's records with [tree] and uploads its media, reading
  /// each original through [source]. Used to load a tree from files.
  ///
  /// Files larger than [maxMediaBytes] are recorded but not uploaded.
  Future<({int records, int uploaded, int skipped})> replaceWith(Tree tree, TreeStore source,
      {int maxMediaBytes = 50 * 1000 * 1000, void Function(String)? progress}) async {
    final writes = <(DocumentReference<Map<String, Object?>>, Map<String, Object?>)>[];
    for (final person in tree.people.values) {
      writes.add((
        _tree.collection('people').doc(person.id),
        _plain({...person.toMap(), 'body': person.body, 'directory': person.directory}),
      ));
    }
    for (final union in tree.unions.values) {
      writes.add((_tree.collection('unions').doc(union.id), _plain(union.toMap())));
    }

    final storage = app.storage().bucket(bucketName).storage;
    var uploaded = 0, skipped = 0;
    for (final media in tree.media.values) {
      final object = 'trees/$treeId/media/${media.fileName}';
      final file = await source.localFile(media);
      if (file.lengthSync() > maxMediaBytes) {
        skipped++;
        progress?.call('skipped ${media.fileName} (${file.lengthSync() ~/ 1000000} MB)');
        continue;
      }
      await storage.uploadObject(bucketName, object, file.readAsBytesSync(),
          metadata: gcs.ObjectMetadata(contentType: contentTypes[media.extension] ?? 'application/octet-stream'));
      writes.add((_tree.collection('media').doc(media.key), _plain(media.toMap(location: object))));
      uploaded++;
      if (uploaded % 25 == 0) progress?.call('uploaded $uploaded files');
    }

    // Firestore accepts at most 500 writes in one batch.
    for (var i = 0; i < writes.length; i += 400) {
      final batch = _db.batch();
      for (final (ref, data) in writes.skip(i).take(400)) {
        batch.set(ref, data);
      }
      await batch.commit();
    }
    final previous = await version();
    await _tree.set({'name': tree.name, 'version': previous + 1});
    return (records: writes.length, uploaded: uploaded, skipped: skipped);
  }

  Future<void> setMember(String email, Role role, {String? name}) =>
      _tree.collection('members').doc(email.toLowerCase()).set({'role': role.name, 'name': ?name});

  /// Records read from YAML use YAML's own map and list types; Firestore
  /// wants plain ones.
  static Map<String, Object?> _plain(Map<String, Object?> map) =>
      (jsonDecode(jsonEncode(map)) as Map).cast<String, Object?>();
}

const contentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'heic': 'image/heic',
  'pdf': 'application/pdf',
  'wmv': 'video/x-ms-wmv',
};
