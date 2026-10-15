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

  final List<FactLine> facts;

  /// The markdown after the facts block.
  final String body;

  /// Lines inside the facts block that are not "Label: value".
  final List<String> strayLines;
}

/// One "Label: value" line.
class FactLine {
  FactLine(this.label, this.value);

  /// The label as written, such as `Occupation`.
  final String label;

  /// Everything after the colon, as written.
  final String value;

  /// The label for matching: lower case, single spaces.
  String get key => label.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  late final List<Segment> segments = Segment.split(value);

  @override
  String toString() => '$label: $value';
}

/// A comma-separated part of a fact line's value.
sealed class Segment {
  const Segment(this.text);

  /// The part as written.
  final String text;

  static final _ref = RegExp(
    r'^@([a-z0-9]+(?:-[a-z0-9]+)*)(?:\s*\(([^)]*)\))?$',
  );
  static final _marked = RegExp(
    r'^\[\s*(date|place)\s*:\s*(.*?)\s*\]$',
    caseSensitive: false,
  );

  /// Splits [value] at commas, except inside `[...]` or `(...)`.
  static List<Segment> split(String value) {
    final parts = <String>[];
    var depth = 0, start = 0;
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c == '[' || c == '(') depth++;
      if ((c == ']' || c == ')') && depth > 0) depth--;
      if (c == ',' && depth == 0) {
        parts.add(value.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(value.substring(start));
    return [
      for (final p in parts.map((p) => p.trim()).where((p) => p.isNotEmpty))
        of(p),
    ];
  }

  static Segment of(String part) {
    final ref = _ref.firstMatch(part);
    if (ref != null) return RefSegment(part, ref[1]!, ref[2]?.trim());
    final marked = _marked.firstMatch(part);
    if (marked != null) {
      return marked[1]!.toLowerCase() == 'date'
          ? DateSegment(part, TreeDate.parse(marked[2]!), marked: true)
          : PlaceSegment(part, marked[2]!, marked: true);
    }
    return TextSegment(part);
  }
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

class DateSegment extends Segment {
  const DateSegment(super.text, this.date, {required this.marked});
  final TreeDate date;
  final bool marked;
}

class PlaceSegment extends Segment {
  const PlaceSegment(super.text, this.place, {required this.marked});
  final String place;
  final bool marked;
}

class TextSegment extends Segment {
  const TextSegment(super.text);
}

/// Finds `@` references in prose. An `@` counts only at the start of a word,
/// so email addresses are left alone.
final proseRef = RegExp(r'(?<![\w@.])@([a-z0-9]+(?:-[a-z0-9]+)*)');

/// Finds `[date: …]` and `[place: …]` in prose.
final proseMarked = RegExp(
  r'\[\s*(date|place)\s*:\s*([^\]]*?)\s*\]',
  caseSensitive: false,
);
