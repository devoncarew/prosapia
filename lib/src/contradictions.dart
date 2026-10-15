import 'tree.dart';

/// One page's claim about how two people are related: the [kind] of line on
/// [page] that names [other]. See page_edits.dart for the kinds.
class Statement {
  Statement(this.page, this.kind, this.label, this.other);

  final String page;
  final String kind;

  /// The line's label, for showing: `Parents`, `Married`.
  final String label;
  final String other;
}

/// Two statements, on the same page or on two, that cannot both be true.
/// Prosapia never chooses between them; it shows the contradiction, and
/// resolving it means removing one of the [statements].
class Contradiction {
  Contradiction(this.message, this.statements);

  final String message;
  final List<Statement> statements;
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
          add(r.id!, mine, Statement(page.id, kind, label, r.id!));
        } else if (r.id == p.id) {
          add(page.id, theirs, Statement(page.id, kind, label, p.id));
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
        ),
      );
    }
  }
  return found;
}

String _both(List<String> relations) => relations.length == 2
    ? 'both ${relations[0]} and ${relations[1]}'
    : '${relations.take(relations.length - 1).join(', ')} and ${relations.last}';
