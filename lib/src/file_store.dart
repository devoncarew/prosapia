import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'dates.dart';
import 'store.dart';
import 'tree.dart';

/// A tree kept as files in Prosapia's portable layout: a markdown file per
/// person, photos with embedded metadata. Used for development, for tests,
/// and to read an export or an import. Anyone who can reach the server can
/// read it; there is no sign-in.
class FileStore extends TreeStore {
  FileStore(this.root);

  final String root;

  @override
  bool get requiresSignIn => false;

  @override
  Future<int> version() async => 0; // Files are read once, at start.

  @override
  Future<Member?> member(String email) async => null;

  @override
  Future<File> localFile(Media media) async => File(media.location);

  @override
  Future<Tree> load() async {
    final settings = File(p.join(root, 'tree.yaml'));
    final name = settings.existsSync()
        ? (loadYaml(settings.readAsStringSync()) as Map)['name'] as String?
        : null;
    final tree = Tree(name ?? p.basename(root));

    for (final dir in _list(p.join(root, 'people')).whereType<Directory>()) {
      final file = File(p.join(dir.path, 'index.md'));
      if (!file.existsSync()) continue;
      final directory = p.basename(dir.path);
      final source = file.readAsStringSync();
      if (source.startsWith('---')) {
        tree.problems.add(
          'people/$directory/index.md is in the old format; '
          'convert it with tool/convert_tree.dart',
        );
        continue;
      }
      final person = Person.fromSource(
        idFromDirectory(directory),
        directory,
        source,
      );
      tree.people[person.id] = person;
    }
    await _loadMedia(tree);
    return tree;
  }

  /// Reads what each media file says about itself. The embedded metadata is
  /// the authority for facts about an image.
  Future<void> _loadMedia(Tree tree) async {
    final dir = p.join(root, 'media');
    final files = _list(dir).whereType<File>().toList();
    if (files.isEmpty) return;

    final embedded = <String, Map<String, dynamic>>{};
    final result = await Process.run('exiftool', [
      '-json',
      '-struct',
      '-q',
      '-XMP-dc:Title',
      '-XMP-dc:Description',
      '-XMP-exif:UserComment',
      '-XMP-iptcExt:PersonInImageWDetails',
      '-XMP-photoshop:DateCreated',
      '-XMP-dc:Coverage',
      '-XMP-iptcExt:LocationShown',
      '-XMP-dc:Relation',
      '-ImageWidth',
      '-ImageHeight',
      dir,
    ], stdoutEncoding: utf8);
    if ((result.stdout as String).trim().isNotEmpty) {
      for (final entry
          in (jsonDecode(result.stdout as String) as List)
              .cast<Map<String, dynamic>>()) {
        embedded[p.basename(entry['SourceFile'] as String)] = entry;
      }
    }

    for (final file in files) {
      final m = Media.namePattern.firstMatch(p.basename(file.path));
      if (m == null) continue;
      // An item without a file is exported as its details, in JSON.
      if (m[3]!.toLowerCase() == 'json') {
        final item = Media.fromMap(
          (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>()
            ..['location'] = '',
        );
        tree.media[item.key] = item;
        continue;
      }
      final item = Media(
        m[1]!,
        isBack: m[2] != null,
        extension: m[3]!.toLowerCase(),
        location: file.path,
      );
      final meta = embedded[p.basename(file.path)] ?? const {};
      item.title = meta['Title']?.toString();
      item.transcription = meta['Description']?.toString();
      item.notes = meta['UserComment']?.toString();
      item.width = meta['ImageWidth'] as int?;
      item.height = meta['ImageHeight'] as int?;
      item.size = file.lengthSync();
      item.date =
          meta['Coverage']?.toString() ??
          dateFromExif(meta['DateCreated']?.toString());
      final shown = meta['LocationShown'];
      if (shown is List && shown.isNotEmpty && shown.first is Map) {
        item.place = (shown.first as Map)['LocationName']?.toString();
      }
      final relations = meta['Relation'];
      for (final relation in relations is List ? relations : [relations]) {
        final set = RegExp(
          '^${Media.idScheme}set:([a-z0-9-]+)#(\\d+)\$',
        ).firstMatch('$relation');
        if (set != null) {
          item.set = set[1];
          item.setIndex = int.parse(set[2]!);
        }
      }
      for (final person
          in (meta['PersonInImageWDetails'] as List?) ?? const []) {
        final ids = (person as Map)['PersonId'];
        for (final id in ids is List ? ids : [ids]) {
          if (id is String && id.startsWith(Media.idScheme)) {
            item.people.add(id.substring(Media.idScheme.length));
          }
        }
      }
      tree.media[item.key] = item;
    }
  }

  static List<FileSystemEntity> _list(String dir) {
    final d = Directory(dir);
    return d.existsSync()
        ? (d.listSync()..sort((a, b) => a.path.compareTo(b.path)))
        : const [];
  }
}

/// A person's id from their directory name: `hughes-thomas-3f8d1a` gives
/// `p-3f8d1a`.
String idFromDirectory(String directory) => 'p-${directory.split('-').last}';

/// A date as written by `photoshop:DateCreated`, `1949:06`, as a person
/// would write it: `June 1949`.
String? dateFromExif(String? value) {
  final m = RegExp(
    r'^(\d{4})(?::(\d{2}))?(?::(\d{2}))?',
  ).firstMatch(value ?? '');
  if (m == null) return null;
  return [
    if (m[3] != null) '${int.parse(m[3]!)}',
    if (m[2] != null) TreeDate.months[int.parse(m[2]!) - 1],
    m[1]!,
  ].join(' ');
}
