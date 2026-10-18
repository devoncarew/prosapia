import 'page_edits.dart' show sameName;
import 'tree.dart';

/// One page's claim about how two people are related: the [kind] of line on
/// [page] that names [other]. See page_edits.dart for the kinds.
class Statement {
  Statement(this.page, this.kind, this.label, this.other, {this.qualifier});

  final String page;
  final String kind;

  /// The line's label, for showing: `Parents`, `Married`.
  final String label;
  final String other;

  /// The kind of relationship, when stated: `adopted`, `step`.
  final String? qualifier;
}

/// Two statements, on the same page or on two, that cannot both be true.
/// Prosapia never chooses between them; it shows the contradiction, and
/// resolving it means removing one of the [statements].
class Contradiction {
  Contradiction(this.message, this.statements, {this.minor = false, this.link});

  final String message;
  final List<Statement> statements;

  /// A small disagreement, such as dates a year apart: worth showing on the
  /// page, but not worth chasing in the list of items to correct.
  final bool minor;

  /// A plain [name] in a [kind] line on [page] that should be a link to
  /// [target]'s page, when that resolves it.
  final ({String page, String kind, String name, String target})? link;

  /// The same contradiction seen from either page has the same key.
  String get key => link != null
      ? 'link ${link!.page} ${link!.kind} ${link!.name}'
      : ([
          for (final s in statements) '${s.page} ${s.kind} ${s.other}',
        ]..sort()).join('; ');
}

/// Contradictions involving [p], which may be a draft not yet saved. Other
/// pages are read from [tree].
List<Contradiction> contradictionsOf(Tree tree, Person p) {
  final found = <Contradiction>[];
  // Everyone [p] is related to, with each statement and what it makes them
  // to [p]: parent, child, sibling or partner.
  final relations = <String, List<(String, Statement)>>{};
  void add(String other, String relation, Statement s) =>
      relations.putIfAbsent(other, () => []).add((relation, s));

  void readPage(Person page, {required bool own}) {
    // On [p]'s own page, a line names the other person; on another page,
    // a line names [p], and the relation is reversed.
    for (final (refs, kind, label, mine, theirs) in [
      (page.parents, 'parents', 'Parents', 'parent', 'child'),
      (page.children, 'children', 'Children', 'child', 'parent'),
      (page.siblings, 'siblings', 'Siblings', 'sibling', 'sibling'),
      (page.partners, 'partner', 'Partner', 'partner', 'partner'),
    ]) {
      for (final r in refs) {
        if (r.id == null) continue;
        if (own) {
          add(
            r.id!,
            mine,
            Statement(page.id, kind, label, r.id!, qualifier: r.qualifier),
          );
        } else if (r.id == p.id) {
          add(
            page.id,
            theirs,
            Statement(page.id, kind, label, p.id, qualifier: r.qualifier),
          );
        }
      }
    }
    for (final c in page.couples) {
      final id = c.partner?.id;
      if (id == null || (!own && id != p.id)) continue;
      final kind = c.kind.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final s = Statement(page.id, kind, c.kind, own ? id : p.id);
      add(own ? id : page.id, 'partner', s);
    }
  }

  readPage(p, own: true);
  for (final other in tree.people.values) {
    if (other.id != p.id) readPage(other, own: false);
  }

  String nameOf(String id) => id == p.id ? p.name : tree.people[id]?.name ?? id;

  relations.forEach((other, list) {
    if (other == p.id) {
      final relation = list.first.$1;
      found.add(
        Contradiction('${p.name} is listed as their own $relation.', [
          for (final (_, s) in list) s,
        ]),
      );
      return;
    }
    final kinds = {for (final (relation, _) in list) relation};
    if (kinds.length > 1) {
      final names = kinds.toList()..sort();
      found.add(
        Contradiction(
          '${nameOf(other)} is listed as ${_both([for (final n in names) "${p.name}'s $n"])}.',
          [for (final (_, s) in list) s],
        ),
      );
    }
  });

  // More than two parents, from this page and others together, unless
  // the extra ones are marked as adoptive, step or the like.
  final parents = <String, List<Statement>>{};
  relations.forEach((other, list) {
    for (final (relation, s) in list) {
      if (relation == 'parent') parents.putIfAbsent(other, () => []).add(s);
    }
  });
  final birthParents = {
    for (final MapEntry(key: id, value: list) in parents.entries)
      if (list.every((s) => s.qualifier == null)) id: list,
  };
  if (birthParents.length > 2) {
    final names = [for (final id in birthParents.keys) nameOf(id)];
    found.add(
      Contradiction(
        '${p.name} is listed with ${birthParents.length} parents: '
        '${names.take(names.length - 1).join(', ')} and ${names.last}.',
        [for (final list in birthParents.values) ...list],
      ),
    );
  }

  // A name written as plain text where that person's own page already
  // states the relationship, so the two are not joined up.
  for (final (refs, kind, label, theirs) in [
    (p.parents, 'parents', 'Parents', 'child'),
    (p.children, 'children', 'Children', 'parent'),
    (p.partners, 'partner', 'Partner', 'partner'),
    (p.siblings, 'siblings', 'Siblings', 'sibling'),
  ]) {
    for (final r in refs) {
      final name = r.name;
      if (r.id != null || name == null) continue;
      for (final other in tree.people.values) {
        if (other.id == p.id ||
            ![other.name, ...other.alsoKnownAs].any((n) => sameName(n, name))) {
          continue;
        }
        final states = (relations[other.id] ?? const []).any(
          (e) => e.$2.page == other.id && e.$1 == _reverse(theirs),
        );
        if (!states) continue;
        found.add(
          Contradiction(
            '“$name” in ${p.name}\'s $label line is not linked, but '
            '${other.name}\'s page already lists ${p.name} as their $theirs.',
            const [],
            link: (page: p.id, kind: kind, name: name, target: other.id),
          ),
        );
      }
    }
  }

  // Brothers or sisters with known parents, but none in common.
  Set<String> parentsOf(String id) {
    final person = tree.people[id];
    return {
      for (final r in person?.parents ?? const <PersonRef>[]) ?r.id,
      for (final other in tree.people.values)
        if (other.children.any((r) => r.id == id)) other.id,
    };
  }

  final mine = parents.keys.toSet();
  relations.forEach((other, list) {
    if (other == p.id || !list.any((e) => e.$1 == 'sibling')) return;
    final theirs = parentsOf(other);
    if (mine.isEmpty ||
        theirs.isEmpty ||
        mine.intersection(theirs).isNotEmpty) {
      return;
    }
    found.add(
      Contradiction(
        '${p.name} and ${nameOf(other)} are listed as brothers or sisters, '
        'but have no parent in common.',
        [
          for (final (relation, s) in list)
            if (relation == 'sibling') s,
        ],
      ),
    );
  });

  // A marriage, or another event of two people, recorded on both pages
  // with different dates or places.
  for (final c in p.couples) {
    final otherId = c.partner?.id;
    final other = otherId == null ? null : tree.people[otherId];
    if (other == null || other.id == p.id) continue;
    final kind = c.kind.toLowerCase();
    for (final d in other.couples) {
      if (d.partner?.id != p.id || d.kind.toLowerCase() != kind) continue;
      final a = c.event, b = d.event;
      final dates =
          a.date != null &&
          b.date != null &&
          a.date!.understood &&
          b.date!.understood &&
          a.date!.sortKey != b.date!.sortKey;
      final places =
          a.place != null &&
          b.place != null &&
          a.place!.toLowerCase().trim() != b.place!.toLowerCase().trim();
      if (!dates && !places) continue;
      // Places written differently, or dates a year or two apart, are the
      // ordinary disagreements of the records.
      final minor = !dates || (a.date!.year! - b.date!.year!).abs() <= 2;
      final what = dates
          ? '${a.date!.raw} on ${p.name}\'s page, ${b.date!.raw} on ${other.name}\'s'
          : '${a.place} on ${p.name}\'s page, ${b.place} on ${other.name}\'s';
      found.add(
        Contradiction(
          'The two pages disagree on ${dates ? 'when' : 'where'} ${p.name} and ${other.name} ${kind == 'married' ? 'married' : 'were ${c.kind.toLowerCase()}'}: $what.',
          [
            Statement(p.id, kind, c.kind, other.id),
            Statement(other.id, kind, d.kind, p.id),
          ],
          minor: minor,
        ),
      );
    }
  }
  return found;
}

/// What a page that states [relation] makes the other person: a page with
/// a Children line naming [p] makes them [p]'s parent.
String _reverse(String relation) => switch (relation) {
  'child' => 'parent',
  'parent' => 'child',
  _ => relation,
};

String _both(List<String> relations) => relations.length == 2
    ? 'both ${relations[0]} and ${relations[1]}'
    : '${relations.take(relations.length - 1).join(', ')} and ${relations.last}';
