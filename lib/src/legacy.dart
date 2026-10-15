import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Converts pages from the earlier format, YAML front matter plus separate
/// partnership records, into the page syntax described in
/// docs/content-model.md.
///
/// [people] maps each person's id to their old structured fields, their
/// prose and their directory. [unions] are the old partnership records.
/// Returns each person's new page text, by id.
Map<String, String> convertLegacy(
  Map<String, ({Map<dynamic, dynamic> fields, String body, String directory})>
  people,
  List<Map<dynamic, dynamic>> unions,
) {
  String ref(String id) {
    final person = people[id];
    return person == null ? '@$id' : '@${person.directory}';
  }

  // A partnership goes on its first partner's page; the other page shows it
  // because a relationship stated on either page counts.
  final couples = <String, List<String>>{};
  for (final union in unions) {
    final partners = (union['partners'] as List).cast<String>();
    if (partners.length < 2) continue;
    final married = union['married'] as Map?;
    final line = married == null
        ? 'Partner: ${ref(partners[1])}'
        : _join([
            'Married: ${ref(partners[1])}',
            if (married['date'] != null) humanDate('${married['date']}'),
            if (married['place'] != null) '${married['place']}',
          ]);
    couples.putIfAbsent(partners[0], () => []).add(line);
  }

  return {
    for (final MapEntry(key: id, value: person) in people.entries)
      id: _page(person.fields, person.body, couples[id] ?? const [], ref),
  };
}

String _page(
  Map<dynamic, dynamic> fields,
  String body,
  List<String> couples,
  String Function(String) ref,
) {
  final lines = <String>['Name: ${fields['name']}'];
  final aka = (fields['also_known_as'] as List?)?.cast<String>() ?? const [];
  if (aka.isNotEmpty) lines.add('Also known as: ${aka.join(', ')}');
  if (fields['sex'] != null) lines.add('Sex: ${fields['sex']}');

  String event(String label, Object? value) {
    if (value is! Map) return '';
    return _join([
      '$label:',
      if (value['date'] != null) humanDate('${value['date']}'),
      if (value['place'] != null) '${value['place']}',
    ]).replaceFirst(': , ', ': ').replaceFirst(':,', ':');
  }

  // Christenings and burials were kept with the other facts; they are life
  // events now.
  final facts =
      (fields['facts'] as List?)?.cast<Map<dynamic, dynamic>>() ?? const [];
  Map<dynamic, dynamic>? factOf(String type) =>
      facts.where((f) => f['type'] == type).firstOrNull;

  for (final (label, value) in [
    ('Born', fields['born']),
    ('Christened', factOf('christening')),
    ('Died', fields['died']),
    ('Buried', factOf('burial')),
  ]) {
    final line = event(label, value);
    if (line.isNotEmpty) lines.add(line);
  }

  final parents = (fields['parents'] as List?) ?? const [];
  if (parents.isNotEmpty) {
    lines.add(
      'Parents: ${parents.map((parent) {
        if (parent is Map) {
          final rel = parent['relationship'];
          return '${ref(parent['id'] as String)}${rel == null ? '' : ' ($rel)'}';
        }
        return ref(parent as String);
      }).join(', ')}',
    );
  }
  lines.addAll(couples);
  if (fields['photo'] != null) lines.add('Photo: ${fields['photo']}');

  const labels = {
    'occupation': 'Occupation',
    'education': 'Education',
    'residence': 'Residence',
    'title': 'Title',
    'degree': 'Degree',
    'graduation': 'Graduated',
    'property': 'Note',
  };
  for (final fact in facts) {
    final type = fact['type'] as String;
    if (type == 'christening' || type == 'burial') continue;
    final label =
        labels[type] ?? '${type[0].toUpperCase()}${type.substring(1)}';
    final value = fact['value']?.toString();
    if (label == 'Note') {
      // A note is free text; its date and place, if any, read best as words.
      lines.add(
        _join([
          'Note: ${value ?? ''}',
          if (fact['place'] != null) '${fact['place']}',
          if (fact['date'] != null) humanDate('${fact['date']}', period: true),
        ]),
      );
      continue;
    }
    // Family Tree Maker puts an employer or a school where a place goes
    // ("US Navy", "Princeton University"); only a residence's place is
    // really a place. The rest stays part of the description.
    final place = fact['place'];
    lines.add(
      _join([
        '$label: ${value ?? ''}',
        if (place != null && type != 'residence') '$place',
        if (fact['date'] != null) humanDate('${fact['date']}', period: true),
        if (place != null && type == 'residence') '[place: $place]',
      ]).replaceFirst(': , ', ': '),
    );
  }

  return '${lines.join('\n')}\n${body.trim().isEmpty ? '' : '\n${body.trim()}\n'}';
}

String _join(List<String> parts) {
  final head = parts.first;
  final rest = parts.skip(1).where((x) => x.isNotEmpty);
  if (rest.isEmpty) return head;
  return head.endsWith(':')
      ? '$head ${rest.join(', ')}'
      : '$head, ${rest.join(', ')}';
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];
const _gedcomMonths = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', //
  'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// Turns a date in the old stored form (ISO, or GEDCOM's grammar) into the
/// way a person would write it: "1950-05-17" becomes "17 May 1950", "ABT
/// 1961" becomes "about 1961". A [period], such as the years of an
/// occupation, reads "1946 to 1987"; otherwise a range reads "between".
String humanDate(String raw, {bool period = false}) {
  String words(String s) => s.replaceAllMapped(RegExp(r'\b([A-Z]{3})\b'), (m) {
    final i = _gedcomMonths.indexOf(m[1]!);
    return i < 0 ? m[1]! : _monthNames[i];
  });
  final iso = RegExp(r'^(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?$').firstMatch(raw);
  if (iso != null) {
    return [
      if (iso[3] != null) '${int.parse(iso[3]!)}',
      if (iso[2] != null) _monthNames[int.parse(iso[2]!) - 1],
      iso[1]!,
    ].join(' ');
  }
  final between = RegExp(r'^BET (.+) AND (.+)$').firstMatch(raw);
  if (between != null) {
    return period
        ? '${words(between[1]!)} to ${words(between[2]!)}'
        : 'between ${words(between[1]!)} and ${words(between[2]!)}';
  }
  const qualifiers = {
    'ABT': 'about', 'CAL': 'about', 'EST': 'about', 'BEF': 'before', //
    'AFT': 'after', 'FROM': 'from', 'TO': 'until',
  };
  final parts = raw.split(' ');
  final q = qualifiers[parts.first];
  return q == null ? words(raw) : '$q ${words(parts.skip(1).join(' '))}';
}

/// Rewrites a tree directory in the old format into the page syntax, in
/// place: each `people/*/index.md` is rewritten and `unions/` is removed.
/// Returns how many pages were converted; pages already converted are left
/// alone.
int convertLegacyTreeDir(String root) {
  final people =
      <
        String,
        ({Map<dynamic, dynamic> fields, String body, String directory})
      >{};
  final files = <String, File>{};
  final peopleDir = Directory(p.join(root, 'people'));
  if (!peopleDir.existsSync()) return 0;
  for (final dir in peopleDir.listSync().whereType<Directory>()) {
    final file = File(p.join(dir.path, 'index.md'));
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    final m = RegExp(
      r'^---\r?\n(.*?)\r?\n---\r?\n?(.*)$',
      dotAll: true,
    ).firstMatch(text);
    if (m == null) continue; // already in the page syntax
    final fields = loadYaml(m[1]!) as Map;
    final id = fields['id'] as String;
    people[id] = (fields: fields, body: m[2]!, directory: p.basename(dir.path));
    files[id] = file;
  }
  final unionsDir = Directory(p.join(root, 'unions'));
  final unions = <Map<dynamic, dynamic>>[];
  if (unionsDir.existsSync()) {
    for (final file in unionsDir.listSync().whereType<File>()) {
      final m = RegExp(
        r'^---\r?\n(.*?)\r?\n---',
        dotAll: true,
      ).firstMatch(file.readAsStringSync());
      if (m != null) unions.add(loadYaml(m[1]!) as Map);
    }
  }
  final converted = convertLegacy(people, unions);
  converted.forEach((id, source) => files[id]!.writeAsStringSync(source));
  if (unionsDir.existsSync()) unionsDir.deleteSync(recursive: true);
  return converted.length;
}
