import 'dates.dart';
import 'page_format.dart';
import 'page_syntax.dart';
import 'tree.dart';

/// Facts whose value is taken whole, as written, not as parts.
const _whole = {'name', 'note', 'sex', 'photo'};

/// A fact line in its normal form, as one or more lines: parts separated by
/// `, `, a value with a comma in quotes, a place or source said to be one,
/// and the line carried on with a two-space indent past [width] columns.
///
/// The line is only rewritten when the new form reads exactly as the old
/// one does; otherwise it is kept as written, with single spaces.
List<String> formatFact(String label, String value, {int width = pageWidth}) {
  final plain = '$label: $value'.trim();
  // A whole value, such as a note, is broken between words; its lines are
  // joined again with a single space, so it reads the same.
  if (_whole.contains(_key(label)) || value.isEmpty) {
    return _words(_spaces(plain), width);
  }
  final parts = _parts(FactLine(label, value));
  final rewritten = '$label: ${parts.join(', ')}';
  if (_meaning(rewritten) != _meaning(plain)) return [_spaces(plain)];
  return _wrap(label, parts, width);
}

String _key(String label) =>
    label.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

String _spaces(String s) => s.trim().replaceAll(RegExp(r'[ \t]+'), ' ');

/// The parts of [line] as they are written in the normal form.
List<String> _parts(FactLine line) {
  final key = line.key;
  final life = Person.lifeEvents.contains(key);
  final couple = Person.coupleEvents.contains(key);
  final relation = Person.relationships.contains(key);
  final names = key == 'nickname' || key == 'also known as';
  final segments = line.segments;

  if (relation || names) {
    return [for (final s in segments) _one(s)];
  }

  // Which plain part, if any, a couple event reads as the partner.
  TextSegment? partner;
  if (couple && segments.whereType<RefSegment>().isEmpty) {
    partner = segments
        .whereType<TextSegment>()
        .where((s) => !TreeDate.parse(s.value).understood)
        .firstOrNull;
  }

  // The plain parts that are read together as one value: the place of an
  // event, or the description of any other fact. They are written as one.
  TreeDate? date;
  var placed = false;
  final joined = <TextSegment>[];
  TextSegment? dated;
  for (final s in segments) {
    if (s is DateSegment) date ??= s.date;
    if (s is PlaceSegment) placed = true;
    if (s is! TextSegment || identical(s, partner)) continue;
    final asDate = TreeDate.parse(s.value);
    // As in reading: after the place, a date needs a year.
    final isDate = (life || couple)
        ? date == null &&
              asDate.understood &&
              ((!placed && joined.isEmpty) || asDate.year != null)
        : date == null && asDate.understood;
    if (isDate) {
      date = asDate;
      dated = s;
    } else {
      joined.add(s);
      if (life || couple) placed = true;
    }
  }
  final value = joined.map((s) => s.value).join(', ');
  // Beside a named partner, a plain part would read as the partner, so the
  // place is said to be one.
  final label = couple && partner != null ? 'place: ' : '';

  final out = <String>[];
  var wroteJoined = false;
  for (final s in segments) {
    if (s is TextSegment && joined.contains(s) && !identical(s, partner)) {
      if (!wroteJoined) out.add('$label${Segment.quote(value)}');
      wroteJoined = true;
    } else if (identical(s, dated)) {
      out.add(Segment.quote(s.value));
    } else {
      out.add(_one(s));
    }
  }
  return out;
}

/// One part on its own, in the normal form.
String _one(Segment s) => switch (s) {
  RefSegment() => _spaces(s.text),
  DateSegment() => 'date: ${Segment.quote(s.date.raw)}',
  PlaceSegment() => 'place: ${Segment.quote(s.place)}',
  SourceSegment() => 'source: ${Segment.quote(s.source)}',
  TextSegment() => Segment.quote(_spaces(s.value)),
};

/// `Label: part, part, …`, carried on to indented lines past [width],
/// breaking only before a part long enough, or labelled, to be worth it.
List<String> _wrap(String label, List<String> parts, int width) {
  final lines = <String>[];
  var line = '$label:';
  for (final (i, part) in parts.indexed) {
    final piece = i < parts.length - 1 ? '$part,' : part;
    final first = line == '$label:';
    // A short part, such as a date, stays with the part before it.
    final worthBreaking = piece.length >= 20 || piece.contains(':');
    if (!first && worthBreaking && line.length + 1 + piece.length > width) {
      lines.add(line);
      line = '  $piece';
    } else {
      line = '$line $piece';
    }
  }
  lines.add(line);
  // A part too long for a line of its own is broken between words: an
  // indented line is joined back with a single space, so it reads the same.
  return [for (final l in lines) ..._words(l, width)];
}

/// [line] broken between words into lines of at most [width], the second
/// and later indented by two spaces.
List<String> _words(String line, int width) {
  if (line.length <= width) return [line];
  final indent = line.startsWith('  ') ? '  ' : '';
  final out = <String>[];
  var current = '';
  for (final word in line.trim().split(' ')) {
    final start = current.isEmpty ? (out.isEmpty ? indent : '  ') : '$current ';
    if (current.isNotEmpty && start.length + word.length > width) {
      out.add(current);
      current = '  $word';
    } else {
      current = '$start$word';
    }
  }
  out.add(current);
  return out;
}

/// What a fact line says, for checking that a rewritten line says the same.
String _meaning(String line) {
  final p = Person.fromSource('p-0', 'x-0', 'Name: X\n$line\n');
  String event(Event? e) =>
      e == null ? '-' : '${e.date?.raw}|${e.place}|${e.sources.join(';')}';
  String ref(PersonRef r) => '${r.id}|${r.name}|${r.qualifier}';
  return [
    event(p.born),
    event(p.christened),
    event(p.died),
    event(p.buried),
    for (final c in p.couples)
      '${c.kind}|${c.partner == null ? '-' : ref(c.partner!)}|${event(c.event)}',
    for (final list in [p.parents, p.children, p.siblings, p.partners])
      list.map(ref).join(';'),
    for (final f in p.facts)
      '${f.label}|${f.description}|${event(f.event)}|${f.people.map(ref).join(';')}',
    p.nicknames.join(';'),
    p.alsoKnownAs.join(';'),
    p.issues.join(';'),
  ].join('\n');
}
