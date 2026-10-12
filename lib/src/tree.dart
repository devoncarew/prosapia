import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'dates.dart';

/// A family tree read from a clone of its repository. Nothing here is stored
/// anywhere else: the files are the record.
class Tree {
  Tree._(this.root, this.name);

  final String root;
  final String name;
  final people = <String, Person>{};
  final unions = <String, Union>{};
  final media = <String, Media>{};

  /// Files that could not be read, with the reason.
  final problems = <String>[];

  static Future<Tree> load(String root) async {
    final settings = File(p.join(root, 'loom.yaml'));
    final name = settings.existsSync()
        ? (loadYaml(settings.readAsStringSync()) as Map)['name'] as String?
        : null;
    final tree = Tree._(root, name ?? p.basename(root));

    for (final dir in _list(p.join(root, 'people')).whereType<Directory>()) {
      final file = File(p.join(dir.path, 'index.md'));
      if (!file.existsSync()) continue;
      tree._read(file, (yaml, body) {
        final person = Person.fromYaml(yaml, body, p.basename(dir.path));
        tree.people[person.id] = person;
      });
    }
    for (final file in _list(p.join(root, 'unions')).whereType<File>()) {
      if (!file.path.endsWith('.md')) continue;
      tree._read(file, (yaml, body) {
        final union = Union.fromYaml(yaml);
        tree.unions[union.id] = union;
      });
    }
    await tree._loadMedia();
    return tree;
  }

  void _read(File file, void Function(YamlMap yaml, String body) use) {
    try {
      final (yaml, body) = splitFrontMatter(file.readAsStringSync());
      use(yaml, body);
    } catch (e) {
      problems.add('${p.relative(file.path, from: root)}: $e');
    }
  }

  /// Reads what each media file says about itself. The embedded metadata is
  /// the authority for facts about an image.
  Future<void> _loadMedia() async {
    final dir = p.join(root, 'media');
    final files = _list(dir).whereType<File>().toList();
    if (files.isEmpty) return;

    final embedded = <String, Map<String, dynamic>>{};
    final result = await Process.run('exiftool', [
      '-json', '-struct', '-q', '-XMP-dc:Title', '-XMP-dc:Description',
      '-XMP-iptcExt:PersonInImageWDetails', '-ImageWidth', '-ImageHeight', dir,
    ], stdoutEncoding: utf8);
    if ((result.stdout as String).trim().isNotEmpty) {
      for (final entry in jsonDecode(result.stdout as String) as List) {
        embedded[p.basename(entry['SourceFile'] as String)] =
            entry as Map<String, dynamic>;
      }
    }

    for (final file in files) {
      final m = Media.idPattern.firstMatch(p.basename(file.path));
      if (m == null) continue;
      final item = Media(m[1]!, isBack: m[2] != null, path: file.path);
      final meta = embedded[p.basename(file.path)] ?? const {};
      item.title = _text(meta['Title']);
      item.description = _text(meta['Description']);
      item.width = meta['ImageWidth'] as int?;
      item.height = meta['ImageHeight'] as int?;
      for (final person in (meta['PersonInImageWDetails'] as List?) ?? const []) {
        final ids = (person as Map)['PersonId'];
        for (final id in ids is List ? ids : [ids]) {
          if (id is String && id.startsWith('loom:')) {
            item.people.add(id.substring(5));
          }
        }
      }
      media[item.key] = item;
    }
  }

  static String? _text(Object? value) => value?.toString();

  static List<FileSystemEntity> _list(String dir) {
    final d = Directory(dir);
    return d.existsSync()
        ? (d.listSync()..sort((a, b) => a.path.compareTo(b.path)))
        : const [];
  }
}

/// Splits a file into its structured block and its markdown body.
(YamlMap, String) splitFrontMatter(String text) {
  final m = RegExp(r'^---\r?\n(.*?)\r?\n---\r?\n?(.*)$', dotAll: true)
      .firstMatch(text);
  if (m == null) throw const FormatException('no front matter');
  return (loadYaml(m[1]!) as YamlMap, m[2]!.trim());
}

class Event {
  Event({this.date, this.place, this.note});

  static Event? fromYaml(Object? yaml) {
    if (yaml is! Map) return null;
    final date = yaml['date'];
    return Event(
      // YAML reads a bare year as a number.
      date: date == null ? null : LoomDate(date.toString()),
      place: yaml['place'] as String?,
      note: yaml['note'] as String?,
    );
  }

  final LoomDate? date;
  final String? place;
  final String? note;
}

/// Something known about a person beyond birth and death: an occupation, a
/// residence, a burial.
class Fact {
  Fact(this.type, this.value, this.event);

  final String type;
  final String? value;
  final Event event;
}

class ParentLink {
  ParentLink(this.id, [this.relationship]);

  final String id;

  /// Set when the parent is not a birth parent: `adopted`, `step`.
  final String? relationship;
}

class Person {
  Person(this.id, this.name, this.directory);

  factory Person.fromYaml(YamlMap yaml, String body, String directory) {
    final person = Person(yaml['id'] as String, yaml['name'] as String, directory)
      ..surname = yaml['surname'] as String?
      ..sex = yaml['sex'] as String?
      ..born = Event.fromYaml(yaml['born'])
      ..died = Event.fromYaml(yaml['died'])
      ..photo = yaml['photo'] as String?
      ..body = body;
    person.alsoKnownAs
        .addAll(((yaml['also_known_as'] as List?) ?? const []).cast<String>());
    for (final parent in (yaml['parents'] as List?) ?? const []) {
      person.parents.add(parent is Map
          ? ParentLink(parent['id'] as String, parent['relationship'] as String?)
          : ParentLink(parent as String));
    }
    for (final fact in (yaml['facts'] as List?) ?? const []) {
      person.facts.add(Fact((fact as Map)['type'] as String,
          fact['value']?.toString(), Event.fromYaml(fact)!));
    }
    return person;
  }

  final String id;
  final String name;

  /// The person's directory under `people/`. Only its trailing id is relied on.
  final String directory;
  String? surname;
  String? sex;
  Event? born;
  Event? died;
  String? photo;
  String body = '';
  final alsoKnownAs = <String>[];
  final parents = <ParentLink>[];
  final facts = <Fact>[];

  /// `1911–1987`, `born 1950`, `died 1987`, or empty.
  String get years {
    final b = born?.date?.year, d = died?.date?.year;
    if (b != null && d != null) return '$b–$d';
    if (b != null) return 'born $b';
    if (d != null) return 'died $d';
    return '';
  }
}

class Union {
  Union(this.id, this.partners, this.married);

  factory Union.fromYaml(YamlMap yaml) => Union(yaml['id'] as String,
      (yaml['partners'] as List).cast<String>(), Event.fromYaml(yaml['married']));

  final String id;
  final List<String> partners;
  final Event? married;
}

class Media {
  Media(this.id, {required this.isBack, required this.path});

  /// `m-5t1q8z.jpg` is a front, `m-5t1q8z-back.jpg` its back.
  static final idPattern = RegExp(r'^(m-[a-z0-9]+)(-back)?\.\w+$');

  final String id;
  final bool isBack;
  final String path;
  String? title;
  String? description;
  int? width, height;

  /// Ids of the people shown, from the file's embedded metadata.
  final people = <String>[];

  String get key => isBack ? '$id-back' : id;
  String get extension => p.extension(path).substring(1).toLowerCase();
  bool get isImage => const {'jpg', 'jpeg', 'heic', 'png'}.contains(extension);
}
