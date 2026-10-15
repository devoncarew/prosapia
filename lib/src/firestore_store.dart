import 'dart:convert';
import 'dart:io';

import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:google_cloud_storage/google_cloud_storage.dart' as gcs;
import 'package:path/path.dart' as p;

import 'page_source.dart';
import 'store.dart';
import 'tree.dart';

/// A tree kept in Firestore, with its photos in Cloud Storage. This is the
/// live record in production.
///
/// ```
/// trees/{tree}                 name, version
///   members/{email}            role, name
///   people/{id}                structured fields, body, directory, revision
///     revisions/{number}       every saved version: source, author, summary, at
///   unions/{id}
///   media/{key}                what each file says about itself
///   changes/{auto}             the log: author, summary, at, pages
/// ```
class FirestoreStore extends TreeStore {
  FirestoreStore(
    this.app,
    this.treeId, {
    required this.bucketName,
    required this.cacheDir,
  });

  final FirebaseApp app;
  final String treeId;
  final String bucketName;

  /// Local scratch space for originals fetched from storage. Safe to delete.
  final String cacheDir;

  late final Firestore _db = app.firestore();
  late final DocumentReference<Map<String, Object?>> _tree = _db
      .collection('trees')
      .doc(treeId);

  @override
  bool get requiresSignIn => true;

  @override
  Future<int> version() async =>
      ((await _tree.get()).data()?['version'] as int?) ?? 0;

  @override
  Future<Member?> member(String email) async {
    final snapshot = await _tree
        .collection('members')
        .doc(email.toLowerCase())
        .get();
    final data = snapshot.data();
    if (data == null) return null;
    return Member(
      email.toLowerCase(),
      Role.values.byName(data['role'] as String),
      name: data['name'] as String?,
    );
  }

  @override
  Future<Tree> load() async {
    final root = (await _tree.get()).data();
    if (root == null) {
      throw StateError('There is no tree named "$treeId" in the database.');
    }
    final tree = Tree(root['name'] as String? ?? treeId);

    final results = await Future.wait([
      _tree.collection('people').get(),
      _tree.collection('unions').get(),
      _tree.collection('media').get(),
    ]);
    void each(
      QuerySnapshot<Map<String, Object?>> docs,
      void Function(Map<String, Object?>) use,
    ) {
      for (final doc in docs.docs) {
        try {
          use(doc.data());
        } catch (e) {
          tree.problems.add('${doc.ref.path}: $e');
        }
      }
    }

    each(results[0], (data) {
      final person = _person(data);
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
      final bytes = await app
          .storage()
          .bucket(bucketName)
          .storage
          .downloadObject(bucketName, media.location);
      file.parent.createSync(recursive: true);
      // Write then rename, so a half-written file is never read.
      File('${file.path}.tmp')
        ..writeAsBytesSync(bytes)
        ..renameSync(file.path);
    }
    return file;
  }

  static Person _person(Map<String, Object?> data) {
    final fields = {...data}
      ..remove('body')
      ..remove('directory')
      ..remove('revision');
    return Person.fromMap(
      fields,
      data['body'] as String? ?? '',
      data['directory'] as String? ?? data['id'] as String,
    )..revision = data['revision'] as int? ?? 0;
  }

  static Map<String, Object?> _personDoc(Person person, int revision) =>
      _plain({
        ...person.toMap(),
        'body': person.body,
        'directory': person.directory,
        'revision': revision,
      });

  // ---------------------------------------------------------------- editing

  @override
  bool get editable => true;

  @override
  Future<SaveResult> savePerson(
    Person person, {
    required int basedOn,
    required Member author,
    required String summary,
  }) {
    final ref = _tree.collection('people').doc(person.id);
    // The page, its revision, the log entry and the tree's version change
    // together or not at all.
    return _db.runTransaction((tx) async {
      final current = (await tx.get(ref)).data();
      final revision = current?['revision'] as int? ?? 0;
      if (revision != basedOn) return SaveResult.conflict(revision);
      final next = revision + 1;
      final stamp = {
        'author': author.email,
        'authorName': ?author.name,
        'summary': summary,
        'at': FieldValue.serverTimestamp,
      };
      tx.set(ref, _personDoc(person, next));
      tx.set(ref.collection('revisions').doc('$next'), {
        'number': next,
        'source': personSource(person),
        ...stamp,
      });
      tx.set(_tree.collection('changes').doc(), {
        'pages': {person.id: next},
        ...stamp,
      });
      tx.update(_tree, {'version': const FieldValue.increment(1)});
      return SaveResult.saved(next);
    });
  }

  @override
  Future<List<Revision>> history(String personId) async {
    final snapshot = await _tree
        .collection('people')
        .doc(personId)
        .collection('revisions')
        .orderBy('number', descending: true)
        .get();
    return [for (final doc in snapshot.docs) _revision(doc.data())];
  }

  @override
  Future<Revision?> revision(String personId, int number) async {
    final data =
        (await _tree
                .collection('people')
                .doc(personId)
                .collection('revisions')
                .doc('$number')
                .get())
            .data();
    return data == null ? null : _revision(data);
  }

  @override
  Future<List<Change>> recentChanges({int limit = 100}) async {
    final snapshot = await _tree
        .collection('changes')
        .orderBy('at', descending: true)
        .limit(limit)
        .get();
    return [
      for (final doc in snapshot.docs)
        Change(
          author: doc.data()['author'] as String,
          authorName: doc.data()['authorName'] as String?,
          summary: doc.data()['summary'] as String,
          at: _time(doc.data()['at']),
          pages: ((doc.data()['pages'] as Map?) ?? const {})
              .cast<String, int>(),
        ),
    ];
  }

  @override
  Future<void> rememberName(Member member, String name) =>
      _tree.collection('members').doc(member.email).update({'name': name});

  static Revision _revision(Map<String, Object?> data) => Revision(
    data['number'] as int,
    data['source'] as String,
    author: data['author'] as String,
    authorName: data['authorName'] as String?,
    summary: data['summary'] as String,
    at: _time(data['at']),
  );

  static DateTime _time(Object? value) => value is Timestamp
      ? value.toDate()
      : DateTime.fromMillisecondsSinceEpoch(0);

  // ----------------------------------------------------------------- writes

  /// Replaces the tree's records with [tree] and uploads its media, reading
  /// each original through [source]. Used to load a tree from files.
  ///
  /// Earlier revisions and log entries are not cleared; this is for setting
  /// a tree up, not for routine use. Files larger than [maxMediaBytes] are
  /// skipped.
  /// Whether a tree with this id exists.
  Future<bool> exists() async => (await _tree.get()).exists;

  /// Deletes the tree's pages, their history, partnerships, media records
  /// and change log. Members are kept, and so are files in storage, which
  /// [replaceWith] reuses when they are unchanged.
  Future<void> clearRecords() async {
    for (final name in ['people', 'unions', 'media', 'changes']) {
      await _db.recursiveDelete(_tree.collection(name));
    }
  }

  Future<({int records, int uploaded, int reused, List<String> skipped})>
  replaceWith(
    Tree tree,
    TreeStore source, {
    int maxMediaBytes = 50 * 1000 * 1000,
    String loadedBy = 'loader',
    void Function(String)? progress,
  }) async {
    final writes =
        <(DocumentReference<Map<String, Object?>>, Map<String, Object?>)>[];
    final stamp = {
      'author': loadedBy,
      'summary': 'Loaded from files',
      'at': FieldValue.serverTimestamp,
    };
    for (final person in tree.people.values) {
      final ref = _tree.collection('people').doc(person.id);
      writes.add((ref, _personDoc(person, 1)));
      writes.add((
        ref.collection('revisions').doc('1'),
        {'number': 1, 'source': personSource(person), ...stamp},
      ));
    }
    writes.add((
      _tree.collection('changes').doc(),
      {
        'pages': {for (final id in tree.people.keys) id: 1},
        ...stamp,
      },
    ));
    for (final union in tree.unions.values) {
      writes.add((
        _tree.collection('unions').doc(union.id),
        _plain(union.toMap()),
      ));
    }

    final storage = app.storage().bucket(bucketName).storage;
    var uploaded = 0, reused = 0;
    final skipped = <String>[];
    for (final media in tree.media.values) {
      final object = 'trees/$treeId/media/${media.fileName}';
      final file = await source.localFile(media);
      final size = file.lengthSync();
      if (size > maxMediaBytes) {
        skipped.add('${media.fileName} (${size ~/ 1000000} MB)');
        continue;
      }
      // A rerun need not upload again what is already there.
      if (await _storedSize(object) == size) {
        reused++;
        writes.add((
          _tree.collection('media').doc(media.key),
          _plain(media.toMap(location: object)),
        ));
        continue;
      }
      await storage.uploadObject(
        bucketName,
        object,
        file.readAsBytesSync(),
        metadata: gcs.ObjectMetadata(
          contentType:
              contentTypes[media.extension] ?? 'application/octet-stream',
        ),
      );
      writes.add((
        _tree.collection('media').doc(media.key),
        _plain(media.toMap(location: object)),
      ));
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
    return (
      records: writes.length,
      uploaded: uploaded,
      reused: reused,
      skipped: skipped,
    );
  }

  /// The size of a stored file, or null if there is none.
  Future<int?> _storedSize(String object) async {
    try {
      final meta = await app
          .storage()
          .bucket(bucketName)
          .storage
          .objectMetadata(bucketName, object);
      return meta.size?.toInt();
    } on gcs.NotFoundException {
      return null;
    }
  }

  Future<void> setMember(String email, Role role, {String? name}) => _tree
      .collection('members')
      .doc(email.toLowerCase())
      .set({'role': role.name, 'name': ?name});

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
