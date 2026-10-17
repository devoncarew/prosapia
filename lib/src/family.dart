import 'index.dart';
import 'tree.dart';

/// A person's close family, two generations each way, laid out as an
/// hourglass: grandparents and parents above, brothers and sisters beside,
/// children and grandchildren below. Anyone further away is reached by
/// centring the chart on someone nearer them.
class Hourglass {
  Hourglass._(this.center);

  /// Builds the hourglass for [center] from the relationships in [index].
  factory Hourglass.of(Person center, Tree tree, Index index) {
    final h = Hourglass._(center);
    bool has(String id) => tree.people.containsKey(id);

    for (final parent in _fatherFirst(index.parentsOf(center.id), tree)) {
      h.parents.add((
        id: parent,
        parents: _fatherFirst(index.parentsOf(parent), tree),
      ));
    }

    h.partners.addAll(index.partnersOf(center.id).where(has));

    // Older brothers and sisters to the left, younger to the right; those
    // with no known birth go to the right, after the rest.
    final born = center.born?.date?.sortKey;
    for (final s in index.siblingsOf(center.id).where(has)) {
      final theirs = tree.people[s]!.born?.date?.sortKey;
      (born != null && theirs != null && theirs < born ? h.older : h.younger)
          .add(s);
    }

    // Children grouped by their other parent: each partner's in turn, then
    // anyone else's, then those whose other parent is not known.
    final groups = <String?, List<Descendant>>{
      for (final p in h.partners) p: [],
    };
    for (final child in index.childrenOf(center.id).where(has)) {
      final others = index.parentsOf(child).where((p) => p != center.id);
      final other =
          others.where(h.partners.contains).firstOrNull ?? others.firstOrNull;
      groups
          .putIfAbsent(other, () => [])
          .add(
            Descendant(
              child,
              partners: index.partnersOf(child).where(has).toList(),
              children: index.childrenOf(child).where(has).toList(),
            ),
          );
    }
    final unknown = groups.remove(null);
    for (final MapEntry(key: other, value: children) in groups.entries) {
      if (children.isNotEmpty) {
        h.children.add((other: other, children: children));
      }
    }
    if (unknown != null) h.children.add((other: null, children: unknown));
    return h;
  }

  final Person center;

  /// Parents, father first, each with their own parents.
  final parents = <({String id, List<String> parents})>[];

  /// Partners, earliest marriage first.
  final partners = <String>[];

  /// Brothers and sisters born before [center], eldest first.
  final older = <String>[];

  /// Brothers and sisters born after [center], or not known to be before.
  final younger = <String>[];

  /// Children, grouped by their other parent; `other` is null when it is
  /// not known.
  final children = <({String? other, List<Descendant> children})>[];

  /// How many people the chart shows, besides [center].
  int get size =>
      parents.length +
      parents.fold<int>(0, (n, p) => n + p.parents.length) +
      partners.length +
      older.length +
      younger.length +
      children.fold<int>(
        0,
        (n, g) => g.children.fold(n, (n, c) => n + 1 + c.children.length),
      );

  /// The person to centre the chart on when no one is chosen: the one whose
  /// chart shows the most people, so a first look shows the most family.
  static Person? busiest(Tree tree, Index index) {
    Person? best;
    var most = -1;
    for (final p in tree.people.values) {
      final n = Hourglass.of(p, tree, index).size;
      if (n > most) {
        best = p;
        most = n;
      }
    }
    return best;
  }

  static List<String> _fatherFirst(List<String> ids, Tree tree) {
    bool male(String id) =>
        tree.people[id]?.sex?.trim().toLowerCase().startsWith('m') ?? false;
    final known = ids.where(tree.people.containsKey).toList();
    return [...known.where(male), ...known.where((id) => !male(id))];
  }
}

/// A child in the chart, with their partners and their own children.
class Descendant {
  Descendant(this.id, {required this.partners, required this.children});

  final String id;
  final List<String> partners;
  final List<String> children;
}
