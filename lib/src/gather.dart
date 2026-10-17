import 'index.dart';
import 'page_syntax.dart';
import 'tree.dart';

/// Something the tree says about a person away from their own page: a
/// paragraph on another page, a close relative's facts, or a photo or
/// document that names them.
class Excerpt {
  Excerpt(this.from, this.text, {this.byName = false});

  /// Where it was found, for the model and the editor: "Michael Carew's
  /// page", "the photo “Lake Compounce”".
  final String from;
  final String text;

  /// Found by a plain name rather than a link, so it may be about someone
  /// else with the same name.
  final bool byName;
}

/// What the tree says about [person] elsewhere, most useful first, up to
/// about [budget] characters: paragraphs on other pages that mention them,
/// their close relatives' facts, and the photos and documents that name
/// them. Given to the model so a first draft can include what is known
/// beyond the person's own page.
List<Excerpt> elsewhere(
  Person person,
  Tree tree,
  Index index, {
  int budget = 20000,
}) {
  final found = <Excerpt>[];
  var used = 0;
  bool add(Excerpt e) {
    if (used + e.text.length > budget) return false;
    used += e.text.length;
    found.add(e);
    return true;
  }

  // Paragraphs on other pages that link to them, or name them.
  final names = _namesOf(person);
  final mentions = <Excerpt>[];
  for (final other in tree.people.values) {
    if (other.id == person.id) continue;
    for (final paragraph in _paragraphs(other.body)) {
      final linked = proseRef
          .allMatches(paragraph)
          .any((m) => 'p-${m[1]!.split('-').last}' == person.id);
      final named =
          !linked &&
          names.any(
            (n) => RegExp(
              '\\b${RegExp.escape(n)}\\b',
              caseSensitive: false,
            ).hasMatch(paragraph),
          );
      if (linked || named) {
        mentions.add(Excerpt("${other.name}'s page", paragraph, byName: named));
      }
    }
  }
  // Linked mentions are surely about them; plain names may not be.
  mentions.sort((a, b) => (a.byName ? 1 : 0).compareTo(b.byName ? 1 : 0));
  for (final e in mentions) {
    add(e);
  }

  // Close relatives' facts, without their relationship lines.
  for (final (relation, ids) in [
    ('parent', index.parentsOf(person.id)),
    ('partner', index.partnersOf(person.id)),
    ('sibling', index.siblingsOf(person.id)),
    ('child', index.childrenOf(person.id)),
  ]) {
    for (final id in ids) {
      final relative = tree.people[id];
      if (relative == null) continue;
      final facts = [
        for (final line in ParsedPage.parse(relative.source).facts)
          if (!_skipped.contains(line.key)) '$line',
      ];
      if (facts.isNotEmpty) {
        add(
          Excerpt(
            "${relative.name}'s facts (${person.name}'s $relation)",
            facts.join('\n'),
          ),
        );
      }
    }
  }

  // Photos and documents that name them.
  for (final key in index.mediaOf(person.id)) {
    final m = tree.media[key];
    if (m == null || m.isBack) continue;
    final back = tree.media['${m.id}-back'];
    final text = [
      if (m.date != null) 'Date: ${m.date}',
      if (m.place != null) 'Place: ${m.place}',
      if (m.people.length > 1)
        'Also named: ${[for (final id in m.people)
          if (id != person.id) tree.people[id]?.name ?? id].join(', ')}',
      if (m.transcription ?? back?.transcription case final writing?)
        'Written on it: ${_clip(writing)}',
      if (m.notes case final notes?) 'Notes: ${_clip(notes)}',
    ];
    if (text.isEmpty) continue;
    add(
      Excerpt(
        'the ${m.isDocument ? 'document' : 'photo'} “${m.title ?? 'Untitled'}”',
        text.join('\n'),
      ),
    );
  }
  return found;
}

/// A long transcription or notes cut to about [length] characters, at a
/// word, so one document does not use up what a draft is given.
String _clip(String text, [int length = 3000]) {
  if (text.length <= length) return text;
  final cut = text.lastIndexOf(RegExp(r'\s'), length);
  return '${text.substring(0, cut > 0 ? cut : length).trimRight()} …';
}

/// The facts a relative's excerpt leaves out: their name is in the heading,
/// and their relationships are given separately.
const _skipped = {
  'name', 'sex',
  'parents', 'parent', 'children', 'child', 'siblings', 'sibling', //
  'partner', 'partners', 'spouse', 'photo',
};

/// The names [person] might be written as in another page's story: their
/// full name, other full names, and given name or nickname with surname.
Set<String> _namesOf(Person person) {
  final words = person.name.trim().split(RegExp(r'\s+'));
  return {
    if (words.length > 1) person.name.trim(),
    for (final other in person.alsoKnownAs)
      if (other.trim().contains(' ')) other.trim(),
    if (words.length > 2) '${words.first} ${words.last}',
    if (words.length > 1)
      for (final nickname in person.nicknames) '$nickname ${words.last}',
  };
}

/// The paragraphs of a story, without its `##` headings.
Iterable<String> _paragraphs(String body) => body
    .split(RegExp(r'\n\s*\n'))
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty && !p.startsWith('#'));
