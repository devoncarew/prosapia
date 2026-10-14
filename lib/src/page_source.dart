import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'tree.dart';

/// A person's page as text: a block of structured facts, then markdown.
/// This is what an editor types, what a revision stores, and what the
/// exported file contains.
String personSource(Person person) =>
    '---\n${toYaml(person.toMap())}---\n${person.body.isEmpty ? '' : '\n${person.body}\n'}';

/// Reads a page back from its text. Throws a [FormatException] whose message
/// can be shown to the person editing.
Person parsePersonSource(String source, {required String id, required String directory}) {
  final (fields, body) = splitFrontMatter(source);
  if (fields['id'] != id) {
    throw FormatException('The id must stay "$id"; it is how other pages refer to this one.');
  }
  final name = fields['name'];
  if (name is! String || name.trim().isEmpty) {
    throw const FormatException('The page needs a name.');
  }
  try {
    return Person.fromMap(fields, body, directory);
  } on TypeError {
    throw const FormatException(
        'One of the facts at the top is not in the expected form. Compare it with the original.');
  }
}

/// Splits page text into its structured block and its markdown body.
(YamlMap, String) splitFrontMatter(String text) {
  final m = RegExp(r'^---\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n(.*))?$', dotAll: true)
      .firstMatch(text.trimLeft());
  if (m == null) {
    throw const FormatException(
        'The page must start with its facts between two lines of three dashes (---).');
  }
  final Object? yaml;
  try {
    yaml = loadYaml(m[1]!);
  } on YamlException catch (e) {
    throw FormatException(
        'The facts at the top could not be read, near line ${e.span!.start.line + 2}: ${e.message}');
  }
  if (yaml is! YamlMap) {
    throw const FormatException('The facts at the top must be a list of "name: value" lines.');
  }
  return (yaml, (m[2] ?? '').replaceAll('\r\n', '\n').trim());
}

/// Writes the subset of YAML that Prosapia's structured blocks use, laid out to
/// be read and edited by hand.
String toYaml(Map<String, Object?> map) {
  final sb = StringBuffer();
  map.forEach((key, value) => _field(sb, key, value, ''));
  return sb.toString();
}

void _field(StringBuffer sb, String key, Object? value, String indent) {
  if (value is Map && value.values.every(_isSimple)) {
    sb.writeln('$indent$key:');
    value.forEach((k, v) => _field(sb, k as String, v, '$indent  '));
  } else if (value is List && value.isNotEmpty && value.any((v) => v is Map)) {
    sb.writeln('$indent$key:');
    for (final item in value) {
      if (item is Map && item.values.every(_isSimple)) {
        var lead = '$indent  - ';
        item.forEach((k, v) {
          sb.writeln('$lead$k: ${_inline(v, key: k as String)}');
          lead = '$indent    ';
        });
      } else {
        sb.writeln('$indent  - ${_inline(item)}');
      }
    }
  } else {
    sb.writeln('$indent$key: ${_inline(value, key: key)}');
  }
}

bool _isSimple(Object? v) => v is! Map && (v is! List || v.every((x) => x is! Map && x is! List));

String _inline(Object? value, {String? key}) {
  if (value is List) return '[${value.map(_inline).join(', ')}]';
  if (value is String) return _scalar(value, isDate: key == 'date');
  return jsonEncode(value); // numbers, booleans, null, and anything unusual
}

final _plain = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 .'/()&-]*$");
final _ambiguous = RegExp(r'^(true|false|yes|no|null|[-+.\d][\d.eE+-]*)$', caseSensitive: false);

/// Dates stay unquoted so they read naturally (`date: 1972`); they are
/// always read back as text.
String _scalar(String v, {bool isDate = false}) {
  final plain = _plain.hasMatch(v) && !v.endsWith(' ') && (isDate || !_ambiguous.hasMatch(v));
  return plain ? v : jsonEncode(v);
}
