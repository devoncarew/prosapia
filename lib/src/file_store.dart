import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'page_source.dart';
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

    void read(File file, void Function(YamlMap yaml, String body) use) {
      try {
        final (yaml, body) = splitFrontMatter(file.readAsStringSync());
        use(yaml, body);
      } catch (e) {
        tree.problems.add('${p.relative(file.path, from: root)}: $e');
      }
    }

    for (final dir in _list(p.join(root, 'people')).whereType<Directory>()) {
      final file = File(p.join(dir.path, 'index.md'));
      if (!file.existsSync()) continue;
      read(file, (yaml, body) {
        final person = Person.fromMap(yaml, body, p.basename(dir.path));
        tree.people[person.id] = person;
      });
    }
    for (final file in _list(p.join(root, 'unions')).whereType<File>()) {
      if (!file.path.endsWith('.md')) continue;
      read(file, (yaml, body) {
        final union = Union.fromMap(yaml);
        tree.unions[union.id] = union;
      });
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
      '-XMP-iptcExt:PersonInImageWDetails',
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
      final item = Media(
        m[1]!,
        isBack: m[2] != null,
        extension: m[3]!.toLowerCase(),
        location: file.path,
      );
      final meta = embedded[p.basename(file.path)] ?? const {};
      item.title = meta['Title']?.toString();
      item.description = meta['Description']?.toString();
      item.width = meta['ImageWidth'] as int?;
      item.height = meta['ImageHeight'] as int?;
      item.size = file.lengthSync();
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
