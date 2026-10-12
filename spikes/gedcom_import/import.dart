// GEDCOM import spike (milestones 0 and 4 in docs/plan.md).
//
// Converts a GEDCOM 5.5.1 export from Family Tree Maker into a sample tree in
// the layout from docs/architecture.md, and copies the photos it refers to out
// of the matching .ftmb backup, writing what is known about each into the file.
//
// Usage:
//   dart run import.dart <export.ged> <out-dir> [backup.ftmb]
//
// Needs exiftool and unzip when a backup is given.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: dart run import.dart <export.ged> <out-dir> [backup.ftmb]');
    exit(64);
  }
  final outDir = args[1];
  final records = parse(File(args[0]).readAsStringSync());
  final byXref = {for (final r in records) if (r.xref != null) r.xref!: r};
  final report = Report();

  final people = records.where((r) => r.tag == 'INDI').toList();
  final families = records.where((r) => r.tag == 'FAM').toList();
  final objects = records.where((r) => r.tag == 'OBJE').toList();

  final ids = <String, String>{};
  for (final r in [...people, ...families, ...objects]) {
    final prefix = {'INDI': 'p', 'FAM': 'u', 'OBJE': 'm'}[r.tag]!;
    final id = '$prefix-${opaqueId(r.xref!)}';
    if (ids.containsValue(id)) throw StateError('id collision on $id');
    ids[r.xref!] = id;
  }

  // Parents come from the family a person is a child of.
  final parents = <String, List<Map<String, String>>>{};
  for (final fam in families) {
    for (final child in fam.all('CHIL')) {
      final list = parents.putIfAbsent(child.value, () => []);
      for (final (role, relTag) in [('HUSB', '_FREL'), ('WIFE', '_MREL')]) {
        final parent = fam.first(role);
        if (parent == null) continue;
        final rel = child.first(relTag)?.value ?? 'Natural';
        // A child can be in several families (adoptive and birth, say), and
        // one parent can appear in more than one of them.
        final id = ids[parent.value]!;
        if (list.any((m) => m['id'] == id)) continue;
        list.add({'id': id, if (rel != 'Natural') 'relationship': rel.toLowerCase()});
      }
    }
  }

  // People.
  for (final p in people) {
    final id = ids[p.xref]!;
    final names = p.all('NAME').toList();
    final primary = names.firstWhere((n) => n.first('TYPE') == null, orElse: () => names.first);
    final y = Yaml();
    y.field('id', id);
    y.field('name', plainName(primary.value));
    final surname = RegExp(r'/([^/]*)/').firstMatch(primary.value)?.group(1);
    if (surname != null && surname.isNotEmpty) y.field('surname', surname);
    final others = [for (final n in names) if (n != primary) plainName(n.value)];
    if (others.isNotEmpty) y.list('also_known_as', others);
    final sex = {'M': 'male', 'F': 'female'}[p.first('SEX')?.value];
    if (sex != null) y.field('sex', sex);
    for (final (tag, key) in [('BIRT', 'born'), ('DEAT', 'died')]) {
      final e = p.first(tag);
      if (e != null) y.map(key, eventFields(e, report));
    }
    final ps = parents[p.xref] ?? const [];
    if (ps.isNotEmpty) {
      if (ps.every((m) => m.length == 1)) {
        y.list('parents', [for (final m in ps) m['id']!]);
      } else {
        y.maps('parents', ps);
      }
    }
    final photo = p.first('_PHOTO');
    if (photo != null) y.field('photo', ids[photo.value]!);

    final facts = <Map<String, String>>[];
    for (final e in p.children) {
      final type = factTypes[e.tag];
      if (type == null) {
        if (!handledPersonTags.contains(e.tag)) report.unmapped('INDI.${e.tag}');
        continue;
      }
      facts.add({'type': type, if (e.value.isNotEmpty) 'value': e.value, ...eventFields(e, report)});
    }
    if (facts.isNotEmpty) y.maps('facts', facts);
    y.field('gedcom_id', p.xref!.replaceAll('@', ''));

    final notes = [
      for (final n in p.all('NOTE'))
        (n.value.startsWith('@') ? byXref[n.value]?.value ?? '' : n.value).trim()
    ].where((t) => t.isNotEmpty);

    write('$outDir/people/${personDir(plainName(primary.value), surname, id)}/index.md', '---\n$y---\n${notes.isEmpty ? '' : '\n${notes.join('\n\n')}\n'}');
    report.people++;
    if (notes.isNotEmpty) report.withProse++;
  }

  // Partnerships. A family with one known parent needs no record: its
  // children already list that parent.
  for (final fam in families) {
    final partners = [for (final role in ['HUSB', 'WIFE']) if (fam.first(role) != null) ids[fam.first(role)!.value]!];
    final marr = fam.first('MARR');
    if (partners.length < 2 && marr == null) continue;
    final id = ids[fam.xref]!;
    final y = Yaml();
    y.field('id', id);
    y.list('partners', partners);
    if (marr != null) {
      y.map('married', {if (marr.value.isNotEmpty) 'note': marr.value, ...eventFields(marr, report)});
    }
    y.field('gedcom_id', fam.xref!.replaceAll('@', ''));
    for (final c in fam.children) {
      if (!const {'HUSB', 'WIFE', 'CHIL', 'MARR'}.contains(c.tag)) report.unmapped('FAM.${c.tag}');
    }
    write('$outDir/unions/$id.md', '---\n$y---\n');
    report.unions++;
  }

  write('$outDir/loom.yaml', 'name: Carew sample tree\nimported_from: ${args[0].split('/').last}\n');

  // Photos.
  final shown = <String, List<Record>>{}; // media xref -> people it is attached to
  for (final p in people) {
    for (final o in [...p.all('OBJE'), ...p.all('_PHOTO')]) {
      final list = shown.putIfAbsent(o.value, () => []);
      if (!list.contains(p)) list.add(p);
    }
  }
  if (args.length > 2) {
    importPhotos(args[2], outDir, objects, ids, shown, report);
  } else {
    report.photosSkipped = objects.length;
  }

  stdout.write(report);
}

const factTypes = {
  'OCCU': 'occupation',
  'EDUC': 'education',
  'RESI': 'residence',
  'BURI': 'burial',
  'CHR': 'christening',
  'GRAD': 'graduation',
  'PROP': 'property',
  'TITL': 'title',
  '_DEG': 'degree',
};

const handledPersonTags = {'NAME', 'SEX', 'BIRT', 'DEAT', 'FAMC', 'FAMS', 'NOTE', 'OBJE', '_PHOTO'};

/// The date, place and coordinates of an event, in the order they are written.
Map<String, String> eventFields(Record e, Report report) {
  final date = e.first('DATE')?.value;
  final place = e.first('PLAC');
  final map = place?.first('MAP');
  for (final c in e.children) {
    if (!const {'DATE', 'PLAC'}.contains(c.tag)) report.unmapped('event.${c.tag}');
  }
  return {
    if (date != null) 'date': convertDate(date, report),
    if (place != null) 'place': place.value,
    if (map != null) 'coordinates': '[${coordinate(map.first('LATI')!.value)}, ${coordinate(map.first('LONG')!.value)}]',
  };
}

const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

/// Exact dates become ISO (1950-05-17, 1987-11, 1972). Anything qualified or
/// ranged stays in GEDCOM's own grammar (ABT 1961, BET 1880 AND 1885).
String convertDate(String date, Report report) {
  final m = RegExp(r'^(?:(\d{1,2}) )?(?:([A-Z]{3}) )?(\d{4})$').firstMatch(date);
  if (m == null || (m[1] != null && m[2] == null)) {
    if (!RegExp(r'^(ABT|BEF|AFT|CAL|EST) |^BET .* AND |^FROM |^TO ').hasMatch(date)) {
      report.oddDates.add(date);
    }
    return date;
  }
  final month = m[2] == null ? null : months.indexOf(m[2]!) + 1;
  if (month == 0) {
    report.oddDates.add(date);
    return date;
  }
  return [
    m[3]!,
    if (month != null) month.toString().padLeft(2, '0'),
    if (m[1] != null) m[1]!.padLeft(2, '0'),
  ].join('-');
}

/// N41.5083 -> 41.5083, W71.2417 -> -71.2417.
String coordinate(String v) => '${'SW'.contains(v[0]) ? '-' : ''}${v.substring(1)}';

/// A readable directory name ending in the id: carew-howard-joseph-tbczm8.
/// Surname first, so a listing groups families. Only the trailing id
/// identifies the person; the rest is never relied on.
String personDir(String name, String? surname, String id) {
  var given = name;
  if (surname != null && surname.isNotEmpty) given = name.replaceFirst(surname, '');
  final slug = '${surname ?? ''} $given'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return '${slug.isEmpty ? '' : '$slug-'}${id.substring(2)}';
}

String plainName(String gedcomName) => gedcomName.replaceAll('/', '').replaceAll(RegExp(r'\s+'), ' ').trim();

void importPhotos(String backup, String outDir, List<Record> objects, Map<String, String> ids,
    Map<String, List<Record>> shown, Report report) {
  final tmp = Directory.systemTemp.createTempSync('loom_import_');
  final names = {for (final o in objects) o: o.first('FILE')!.value.split(RegExp(r'[\\/]')).last};
  final listing = (Process.runSync('unzip', ['-Z1', backup]).stdout as String).split('\n').toSet();
  final wanted = <Record, String>{}; // record -> path inside the backup
  for (final o in objects) {
    final match = listing.where((l) => l.split('/').last == names[o]);
    if (match.isEmpty) {
      report.photosMissing.add(names[o]!);
    } else {
      wanted[o] = match.first;
    }
  }
  // unzip treats [ and ] in names as patterns; escape them.
  final res = Process.runSync('unzip', [
    '-q', '-o', '-j', backup,
    // Two records may refer to one file; name it once.
    for (final path in wanted.values.toSet()) path.replaceAllMapped(RegExp(r'[\[\]*?]'), (m) => '\\${m[0]}'),
    '-d', tmp.path,
  ]);
  if (res.exitCode > 1) throw StateError('unzip failed: ${res.stderr}');

  Directory('$outDir/media').createSync(recursive: true);
  final argfile = StringBuffer();
  for (final o in wanted.keys) {
    final src = File('${tmp.path}/${names[o]}');
    if (!src.existsSync()) {
      report.photosMissing.add(names[o]!);
      continue;
    }
    final id = ids[o.xref]!;
    // The export labels every file "jpg"; trust the file's own extension.
    final ext = names[o]!.split('.').last.toLowerCase();
    final dest = '$outDir/media/$id.${ext == 'jpeg' ? 'jpg' : ext}';
    report.mediaTypes[ext] = (report.mediaTypes[ext] ?? 0) + 1;
    src.copySync(dest);
    final file = o.first('FILE')!;
    final title = file.first('TITL')?.value;
    final text = file.first('_TEXT')?.value;
    // Metadata only: the image data is not re-encoded.
    argfile
      ..writeln('-overwrite_original')
      ..writeln('-XMP-dc:Identifier=loom:$id');
    if (title != null) argfile.writeln('-XMP-dc:Title=$title');
    if (text != null) argfile.writeln('-XMP-dc:Description=$text');
    final persons = shown[o.xref] ?? const [];
    if (persons.isNotEmpty) {
      argfile.writeln('-XMP-iptcExt:PersonInImage=');
      final structs = <String>[];
      for (final p in persons) {
        final name = plainName(p.first('NAME')!.value);
        argfile.writeln('-XMP-iptcExt:PersonInImage+=$name');
        structs.add('{PersonName=${escapeStruct(name)},PersonId=[loom:${ids[p.xref]}]}');
      }
      argfile.writeln('-XMP-iptcExt:PersonInImageWDetails=[${structs.join(',')}]');
    }
    argfile
      ..writeln(dest)
      ..writeln('-execute');
    report.photos++;
    if (title == null) report.photosUntitled++;
    if (persons.isEmpty) report.photosNoPeople++;
  }
  final argPath = '${tmp.path}/args.txt';
  File(argPath).writeAsStringSync(argfile.toString());
  final exif = Process.runSync('exiftool', ['-q', '-@', argPath]);
  if ((exif.stderr as String).trim().isNotEmpty) report.exifWarnings = (exif.stderr as String).trim();
  tmp.deleteSync(recursive: true);
}

String escapeStruct(String s) => s.replaceAllMapped(RegExp(r'[,\[\]{}|]'), (m) => '|${m[0]}');

void write(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// A short stable id derived from the GEDCOM reference, so that importing the
/// same file twice gives the same ids.
String opaqueId(String xref) {
  const alphabet = '23456789abcdefghjkmnpqrstvwxyz'; // no 0/o, 1/i/l, u
  var h = 0xcbf29ce484222325;
  for (final c in utf8.encode('carew-sample:$xref')) {
    h = ((h ^ c) * 0x100000001b3) & 0x7fffffffffffffff;
  }
  final sb = StringBuffer();
  for (var i = 0; i < 6; i++) {
    sb.write(alphabet[h % alphabet.length]);
    h ~/= alphabet.length;
  }
  return sb.toString();
}

// ------------------------------------------------------------------ GEDCOM

class Record {
  Record(this.level, this.xref, this.tag, this.value);
  final int level;
  final String? xref;
  final String tag;
  String value;
  final children = <Record>[];

  Record? first(String t) => children.where((c) => c.tag == t).firstOrNull;
  Iterable<Record> all(String t) => children.where((c) => c.tag == t);
}

/// Parses GEDCOM text into its top-level records. CONC and CONT lines are
/// folded into the value of the line they continue.
List<Record> parse(String text) {
  final top = <Record>[];
  final stack = <Record>[];
  final line = RegExp(r'^(\d+) (?:(@[^@]+@) )?(\S+)(?: (.*))?$');
  for (var raw in const LineSplitter().convert(text)) {
    raw = raw.replaceFirst('﻿', '');
    final m = line.firstMatch(raw);
    if (m == null) continue;
    final level = int.parse(m[1]!);
    final r = Record(level, m[2], m[3]!, m[4] ?? '');
    while (stack.length > level) {
      stack.removeLast();
    }
    if (r.tag == 'CONC') {
      stack.last.value += r.value;
    } else if (r.tag == 'CONT') {
      stack.last.value += '\n${r.value}';
    } else {
      (level == 0 ? top : stack.last.children).add(r);
      stack.add(r);
    }
  }
  return top;
}

// -------------------------------------------------------------------- YAML

/// Writes the small subset of YAML that Loom's front matter uses.
class Yaml {
  final _sb = StringBuffer();

  void field(String key, String value) => _sb.writeln('$key: ${scalar(value)}');

  void list(String key, List<String> values) => _sb.writeln('$key: [${values.map(scalar).join(', ')}]');

  void map(String key, Map<String, String> fields) {
    _sb.writeln('$key:');
    fields.forEach((k, v) => _sb.writeln('  $k: ${scalar(v, raw: k == 'coordinates')}'));
  }

  void maps(String key, List<Map<String, String>> items) {
    _sb.writeln('$key:');
    for (final item in items) {
      var lead = '  - ';
      item.forEach((k, v) {
        _sb.writeln('$lead$k: ${scalar(v, raw: k == 'coordinates')}');
        lead = '    ';
      });
    }
  }

  static String scalar(String v, {bool raw = false}) {
    if (raw) return v;
    final plain = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 .'/()&-]*$").hasMatch(v) && !v.endsWith(' ');
    return plain ? v : jsonEncode(v);
  }

  @override
  String toString() => _sb.toString();
}

// ------------------------------------------------------------------ report

class Report {
  int people = 0, withProse = 0, unions = 0;
  int photos = 0, photosUntitled = 0, photosNoPeople = 0, photosSkipped = 0;
  final photosMissing = <String>[];
  final oddDates = <String>[];
  final mediaTypes = <String, int>{};
  final _unmapped = <String, int>{};
  String? exifWarnings;

  void unmapped(String path) => _unmapped[path] = (_unmapped[path] ?? 0) + 1;

  @override
  String toString() => [
        'people: $people ($withProse with prose)',
        'unions: $unions',
        'photos: $photos copied, $photosUntitled untitled, $photosNoPeople attached to nobody'
            '${photosSkipped > 0 ? ', $photosSkipped skipped (no backup given)' : ''}',
        if (mediaTypes.isNotEmpty) 'media types: $mediaTypes',
        if (photosMissing.isNotEmpty) 'photos not found in backup: ${photosMissing.length}: ${photosMissing.take(5).join(', ')}',
        if (oddDates.isNotEmpty) 'dates kept as written: ${oddDates.toSet().join(' | ')}',
        if (_unmapped.isNotEmpty) 'not imported: $_unmapped',
        if (exifWarnings != null) 'exiftool: $exifWarnings',
        '',
      ].join('\n');
}
