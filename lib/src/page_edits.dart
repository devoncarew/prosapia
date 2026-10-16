/// Changes that page actions make to a page's text. Each one edits only the
/// lines it must and leaves the rest exactly as written.
///
/// A relationship is named by its kind: `parents`, `children`, `siblings` or
/// `partner` for relationship lines, or a two-person event's label in lower
/// case, such as `married`, for lines that name a partner first.
library;

import 'page_syntax.dart';
import 'tree.dart';

/// The labels that write each kind of relationship line.
const relationLabels = {
  'parents': {'parents', 'parent'},
  'children': {'children', 'child'},
  'siblings': {'siblings', 'sibling'},
  'partner': {'partner', 'partners', 'spouse'},
};

/// The kind of relationship a label writes, or null for other facts.
String? kindOf(String key) {
  for (final MapEntry(key: kind, value: labels) in relationLabels.entries) {
    if (labels.contains(key)) return kind;
  }
  return Person.coupleEvents.contains(key) ? key : null;
}

/// Replaces the plain name [name] in a [kind] line with [reference], keeping
/// any qualifier: `Mary Ducker (adopted)` becomes `@ducker-mary-x2 (adopted)`.
/// Returns null if the page has no such name in such a line.
String? nameToReference(
  String source,
  String kind,
  String name,
  String reference,
) {
  var done = false;
  return _editFacts(source, (line) {
    if (done || kindOf(line.key) != kind) return null;
    final segments = line.segments;
    final couple = !relationLabels.containsKey(kind);
    for (final (i, segment) in segments.indexed) {
      if (couple && i > 0) break; // the partner is named first
      if (segment is! TextSegment) continue;
      final (written, qualifier) = splitQualifier(segment.text);
      if (!sameName(written, name)) continue;
      done = true;
      return [
        for (final (j, s) in segments.indexed)
          j == i
              ? '$reference${qualifier == null ? '' : ' ($qualifier)'}'
              : s.text,
      ];
    }
    return null;
  });
}

/// Removes what a [kind] line says about [personId]: their reference from a
/// relationship line, dropping the line if nothing is left, or a whole
/// two-person event line that names them. Returns null if nothing matched.
String? removeRelation(String source, String kind, String personId) =>
    _editFacts(source, (line) {
      if (kindOf(line.key) != kind) return null;
      final segments = line.segments;
      bool names(Segment s) => s is RefSegment && s.personId == personId;
      if (!relationLabels.containsKey(kind)) {
        return segments.isNotEmpty && names(segments.first) ? const [] : null;
      }
      if (!segments.any(names)) return null;
      return [
        for (final s in segments)
          if (!names(s)) s.text,
      ];
    });

/// Whether [source] refers to [personId] anywhere, in facts or in prose.
bool mentions(String source, String personId) => proseRef
    .allMatches(source)
    .any((m) => 'p-${m[1]!.split('-').last}' == personId);

/// Replaces every reference to [personId] with the plain name [name], for
/// when their page is deleted: the relationship and the story keep their
/// meaning, and the name can be given a page again later.
String referencesToName(String source, String personId, String name) {
  // A comma would split the name into two parts of a fact line.
  final plain = name.replaceAll(',', '').trim();
  return source.replaceAllMapped(
    proseRef,
    (m) => 'p-${m[1]!.split('-').last}' == personId ? plain : m[0]!,
  );
}

/// What [deleted]'s page says about [otherId] that the other page does
/// not, written from the other side with [deleted]'s plain name, for when
/// [deleted]'s page goes: `Partner: @dwyer-lisa-x` on [deleted]'s page
/// becomes `Partner: Something Madej` on Lisa's. Returns [source], the
/// other page, with those lines added, or null if there are none.
String? keepRelations(String source, Person deleted, String otherId) {
  if (mentions(source, deleted.id)) return null;
  const inverse = {
    'parents': 'children',
    'children': 'parents',
    'siblings': 'siblings',
    'partner': 'partner',
  };
  final name = deleted.name.replaceAll(',', '').trim();
  var result = source;
  var changed = false;
  for (final line in ParsedPage.parse(deleted.source).facts) {
    final kind = kindOf(line.key);
    if (kind == null) continue;
    final segments = line.segments;
    if (inverse[kind] case final mine?) {
      for (final s in segments) {
        if (s is RefSegment && s.personId == otherId) {
          final text = s.qualifier == null ? name : '$name (${s.qualifier})';
          result = _addToRelation(result, mine, text) ?? result;
          changed = true;
        }
      }
    } else if (segments.isNotEmpty &&
        segments.first is RefSegment &&
        (segments.first as RefSegment).personId == otherId) {
      // A two-person event: the same line, naming [deleted] instead.
      final rest = [name, ...segments.skip(1).map((s) => s.text)];
      result = _addLine(result, line.label, rest.join(', ')) ?? result;
      changed = true;
    }
  }
  return changed ? result : null;
}

/// Adds [text] to the first [kind] relationship line, or a new line.
String? _addToRelation(String source, String kind, String text) {
  var done = false;
  final changed = _editFacts(source, (line) {
    if (done || kindOf(line.key) != kind) return null;
    done = true;
    return [...line.segments.map((s) => s.text), text];
  });
  return changed ??
      _addLine(source, '${kind[0].toUpperCase()}${kind.substring(1)}', text);
}

/// Adds a `[label]: [value]` line at the end of the facts block. Returns
/// null if the page has no facts block.
String? _addLine(String source, String label, String value) {
  final lines = source.split('\n');
  var i = 0;
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  if (i >= lines.length ||
      ParsedPage.labelPattern.firstMatch(lines[i])?[1]?.toLowerCase() !=
          'name') {
    return null;
  }
  while (i < lines.length && lines[i].trim().isNotEmpty) {
    i++;
  }
  lines.insert(i, '$label: $value');
  return lines.join('\n');
}

/// Sets the first `[label]:` line to [value], or adds one at the end of
/// the facts block. Returns null if the page has no facts block.
String? setFact(String source, String label, String value) {
  final key = label.toLowerCase();
  var done = false;
  final changed = _editFacts(source, (line) {
    if (done || line.key != key) return null;
    done = true;
    return [value];
  });
  return changed ?? _addLine(source, label, value);
}

/// The text of a new page: its name, and what is known from where it was
/// made.
String newPage({
  required String name,
  String born = '',
  List<String> parents = const [],
  List<String> partners = const [],
}) => [
  'Name: ${name.trim()}',
  if (born.trim().isNotEmpty) 'Born: ${born.trim()}',
  if (parents.isNotEmpty) 'Parents: ${parents.join(', ')}',
  if (partners.isNotEmpty) 'Partner: ${partners.join(', ')}',
  '',
].join('\n');

/// `Mary Ducker (adopted)` gives (`Mary Ducker`, `adopted`).
(String, String?) splitQualifier(String text) {
  final m = _qualified.firstMatch(text);
  return m == null ? (text.trim(), null) : (m[1]!.trim(), m[2]!.trim());
}

final _qualified = RegExp(r'^(.*?)\s*\(([^)]*)\)$');

/// Whether two names are written the same, ignoring case and spacing.
bool sameName(String a, String b) => _normal(a) == _normal(b);

String _normal(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// A readable directory name ending in the id, surname first so a listing
/// groups families: `ducker-mary-x2k9ab`.
String directoryFor(String name, String id) {
  final words = name.trim().split(RegExp(r'\s+'));
  final ordered = words.length > 1
      ? [words.last, ...words.take(words.length - 1)]
      : words;
  final slug = ordered
      .join(' ')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final suffix = id.substring(2);
  return slug.isEmpty ? suffix : '$slug-$suffix';
}

/// Applies [edit] to each fact line. [edit] returns the line's new parts,
/// an empty list to remove the line, or null to leave it as written.
/// Returns null if no line changed.
String? _editFacts(String source, List<String>? Function(FactLine) edit) {
  final lines = source.split('\n');
  var i = 0;
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  if (i >= lines.length ||
      ParsedPage.labelPattern.firstMatch(lines[i])?[1]?.toLowerCase() !=
          'name') {
    return null;
  }
  var changed = false;
  final out = lines.sublist(0, i);
  for (; i < lines.length && lines[i].trim().isNotEmpty; i++) {
    final m = ParsedPage.labelPattern.firstMatch(lines[i]);
    final parts = m == null ? null : edit(FactLine(m[1]!.trim(), m[2]!.trim()));
    if (parts == null) {
      out.add(lines[i]);
      continue;
    }
    changed = true;
    if (parts.isNotEmpty) out.add('${m![1]!.trim()}: ${parts.join(', ')}');
  }
  out.addAll(lines.skip(i));
  return changed ? out.join('\n') : null;
}
