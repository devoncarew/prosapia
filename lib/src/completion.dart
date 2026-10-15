import 'index.dart';
import 'page_syntax.dart';
import 'tree.dart';

/// Suggestions for the editor and the search box, drawn from what the tree
/// already holds.
class Completion {
  Completion(this.tree, this.index);

  final Tree tree;
  final Index index;

  /// People whose names match [query]: each word typed must start a word of
  /// their name, or of a name they were also known by.
  List<Map<String, String>> people(String query, {int limit = 10}) {
    final words = _words(query);
    if (words.isEmpty) return const [];
    final matches = <(int, Person)>[];
    for (final p in tree.people.values) {
      for (final name in [p.name, ...p.alsoKnownAs]) {
        final nameWords = _words(name);
        if (words.every((w) => nameWords.any((n) => n.startsWith(w)))) {
          // Names that start with what was typed come first.
          matches.add((nameWords.first.startsWith(words.first) ? 0 : 1, p));
          break;
        }
      }
    }
    matches.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.name.compareTo(b.$2.name);
    });
    return [
      for (final (_, p) in matches.take(limit))
        {'id': p.id, 'ref': p.reference, 'name': p.name, 'detail': _detail(p)},
    ];
  }

  /// "1911–1987, child of Joseph J. Carew and Irene Genevive Howard", to
  /// tell namesakes apart.
  String _detail(Person p) {
    final parents = index
        .parentsOf(p.id)
        .map((id) => tree.people[id]!.name)
        .toList();
    return [
      if (p.years.isNotEmpty) p.years,
      if (parents.isNotEmpty) 'child of ${parents.join(' and ')}',
    ].join(', ');
  }

  late final Map<String, int> _places = () {
    final counts = <String, int>{};
    void add(String? place) {
      if (place == null || place.trim().isEmpty) return;
      counts[place.trim()] = (counts[place.trim()] ?? 0) + 1;
    }

    for (final p in tree.people.values) {
      for (final e in [p.born, p.christened, p.died, p.buried]) {
        add(e?.place);
      }
      for (final c in p.couples) {
        add(c.event.place);
      }
      for (final f in p.facts) {
        add(f.event.place);
      }
      for (final m in proseMarked.allMatches(p.body)) {
        if (m[1]!.toLowerCase() == 'place') add(m[2]);
      }
    }
    return counts;
  }();

  /// Places already used in the tree that contain [query], most used first.
  List<String> places(String query, {int limit = 10}) {
    final q = query.trim().toLowerCase();
    final matches =
        _places.entries
            .where((e) => q.isEmpty || e.key.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) {
            final starts =
                (b.key.toLowerCase().startsWith(q) ? 1 : 0) -
                (a.key.toLowerCase().startsWith(q) ? 1 : 0);
            return starts != 0 ? starts : b.value.compareTo(a.value);
          });
    return [for (final e in matches.take(limit)) e.key];
  }

  static List<String> _words(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();
}
