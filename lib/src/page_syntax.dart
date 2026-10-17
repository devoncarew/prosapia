import 'dates.dart';

/// Reads a page as written: a block of "Label: value" fact lines starting
/// with `Name:`, then markdown prose. Nothing is rejected: a line that does
/// not fit is kept and reported, so the page can show it as not understood.
/// The syntax is described in docs/content-model.md.
class ParsedPage {
  ParsedPage._(this.facts, this.body, this.strayLines);

  factory ParsedPage.parse(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    var i = 0;
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    final facts = <FactLine>[];
    final stray = <String>[];
    if (i < lines.length &&
        labelPattern.firstMatch(lines[i])?[1]?.toLowerCase() == 'name') {
      for (; i < lines.length && lines[i].trim().isNotEmpty; i++) {
        // An indented line carries on the fact above it.
        if (continues(lines[i]) && facts.isNotEmpty) {
          final last = facts.removeLast();
          facts.add(
            FactLine(
              last.label,
              '${last.value} ${lines[i].trim()}'.trim(),
              lines: last.lines + 1,
            ),
          );
          continue;
        }
        final m = labelPattern.firstMatch(lines[i]);
        if (m == null) {
          stray.add(lines[i]);
        } else {
          facts.add(FactLine(m[1]!.trim(), m[2]!.trim()));
        }
      }
    }
    return ParsedPage._(facts, lines.skip(i).join('\n').trim(), stray);
  }

  /// A "Label: value" line.
  static final labelPattern = RegExp(
    r'^\s*([A-Za-z][A-Za-z ]{0,30}?)\s*:\s*(.*)$',
  );

  /// Whether [line], in the facts block, carries on the fact above it: it
  /// starts with two spaces or a tab.
  static bool continues(String line) =>
      line.startsWith('  ') || line.startsWith('\t');

  final List<FactLine> facts;

  /// The markdown after the facts block.
  final String body;

  /// Lines inside the facts block that are not "Label: value".
  final List<String> strayLines;
}

/// One "Label: value" fact, which may be written over several lines.
class FactLine {
  FactLine(this.label, this.value, {this.lines = 1});

  /// The label as written, such as `Occupation`.
  final String label;

  /// Everything after the colon, as written, with any continuation lines
  /// joined by a space.
  final String value;

  /// How many lines of the page the fact is written on.
  final int lines;

  /// The label for matching: lower case, single spaces.
  String get key => label.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  late final List<Segment> segments = Segment.split(value);

  @override
  String toString() => '$label: $value';
}

/// A part of a fact line's value. Parts are separated by commas; a value
/// that contains a comma is quoted, as in `"Brooklyn, NY"`. A part can say
/// what it is, as in `place: "Brooklyn, NY"`, or be known by its form: an
/// `@` reference, or a date.
sealed class Segment {
  const Segment(this.text);

  /// The part as written.
  final String text;

  /// What the part says: [text] without its label or quotes.
  String get value => text;

  static final _ref = RegExp(
    r'^@([a-z0-9]+(?:-[a-z0-9]+)*)(?:\s*\(([^)]*)\))?$',
  );
  static final _marked = RegExp(
    r'^\[\s*(date|place)\s*:\s*(.*?)\s*\]$',
    caseSensitive: false,
  );
  static final _labelled = RegExp(
    r'^(date|place|source)\s*:\s*(.*)$',
    caseSensitive: false,
  );

  /// The labels a part can be given.
  static const labels = ['date', 'place', 'source'];

  /// Splits [value] at commas, except inside quotes, `[...]` or `(...)`.
  /// Where an unquoted comma splits a date, as in `January 6, 1990`, the
  /// date is read whole.
  static List<Segment> split(String value) {
    final parts = <String>[];
    var depth = 0, start = 0;
    var quoted = false;
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c == '"') quoted = !quoted;
      if (quoted) continue;
      if (c == '[' || c == '(') depth++;
      if ((c == ']' || c == ')') && depth > 0) depth--;
      if (c == ',' && depth == 0) {
        parts.add(value.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(value.substring(start));
    final segments = [
      for (final p in parts.map((p) => p.trim()).where((p) => p.isNotEmpty))
        of(p),
    ];
    // Forgiving: "January 6" and "1990" read together as one date.
    for (var i = 0; i + 1 < segments.length; i++) {
      final a = segments[i], b = segments[i + 1];
      if (a is TextSegment &&
          b is TextSegment &&
          !a.quoted &&
          !b.quoted &&
          !TreeDate.parse(a.text).understood &&
          TreeDate.parse('${a.text}, ${b.text}').understood) {
        segments[i] = TextSegment('${a.text}, ${b.text}');
        segments.removeAt(i + 1);
      }
    }
    return segments;
  }

  static Segment of(String part) {
    final ref = _ref.firstMatch(part);
    if (ref != null) return RefSegment(part, ref[1]!, ref[2]?.trim());
    final marked = _marked.firstMatch(part) ?? _labelled.firstMatch(part);
    if (marked != null) {
      final what = unquote(marked[2]!.trim());
      return switch (marked[1]!.toLowerCase()) {
        'date' => DateSegment(part, TreeDate.parse(what), marked: true),
        'place' => PlaceSegment(part, what, marked: true),
        _ => SourceSegment(part, what),
      };
    }
    return TextSegment(part);
  }

  /// Whether [part] is wholly one quoted value.
  static bool isQuoted(String part) =>
      part.length >= 2 &&
      part.startsWith('"') &&
      part.endsWith('"') &&
      !part.substring(1, part.length - 1).replaceAll('""', '').contains('"');

  /// [part] without its quotes, with doubled quotes inside made single.
  static String unquote(String part) => isQuoted(part)
      ? part.substring(1, part.length - 1).replaceAll('""', '"')
      : part;

  /// [value] as a part: quoted if it has a comma or a quote, so it reads
  /// back as one part.
  static String quote(String value) =>
      value.contains(',') || value.contains('"') || value.contains('@')
      ? '"${value.replaceAll('"', '""')}"'
      : value;
}

/// `@hughes-thomas-3f8d1a`, optionally followed by a qualifier in
/// parentheses, such as `(adopted)`.
class RefSegment extends Segment {
  const RefSegment(super.text, this.token, this.qualifier);

  /// What follows the `@`.
  final String token;
  final String? qualifier;

  /// The person id the reference names: the token's last part, which is the
  /// id in both `@hughes-thomas-3f8d1a` and `@p-3f8d1a`.
  String get personId => 'p-${token.split('-').last}';
}

/// A date said to be one: `date: 1925`, or `[date: 1925]`.
class DateSegment extends Segment {
  const DateSegment(super.text, this.date, {required this.marked});
  final TreeDate date;
  final bool marked;

  @override
  String get value => date.raw;
}

/// A place said to be one: `place: "Hartford, CT"`, or `[place: …]`.
class PlaceSegment extends Segment {
  const PlaceSegment(super.text, this.place, {required this.marked});
  final String place;
  final bool marked;

  @override
  String get value => place;
}

/// Where a fact comes from: `source: "1920 census, Hartford, CT"`.
class SourceSegment extends Segment {
  const SourceSegment(super.text, this.source);
  final String source;

  @override
  String get value => source;
}

/// Any other part: a name, a description, or a date or place known by its
/// form and its place in the line.
class TextSegment extends Segment {
  const TextSegment(super.text);

  /// Whether it is written in quotes, as one value.
  bool get quoted => Segment.isQuoted(text);

  @override
  String get value => Segment.unquote(text);
}

/// Finds `@` references in prose. An `@` counts only at the start of a word,
/// so email addresses are left alone.
final proseRef = RegExp(r'(?<![\w@.])@([a-z0-9]+(?:-[a-z0-9]+)*)');

/// Finds `[date: …]` and `[place: …]` in prose.
final proseMarked = RegExp(
  r'\[\s*(date|place)\s*:\s*([^\]]*?)\s*\]',
  caseSensitive: false,
);
