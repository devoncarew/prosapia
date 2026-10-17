import 'package:prosapia/src/family.dart';
import 'package:prosapia/src/index.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  final tree = Tree('test');
  for (final (dir, source) in [
    ('grand-a1a1a1', 'Name: Grand Father\nSex: male\n'),
    ('dad-b2b2b2', 'Name: Dad\nSex: male\nParents: @grand-a1a1a1\n'),
    ('mum-c3c3c3', 'Name: Mum\nSex: female\nPartner: @dad-b2b2b2\n'),
    (
      'me-d4d4d4',
      'Name: Me\nBorn: 1950\nParents: @mum-c3c3c3, @dad-b2b2b2\n'
          'Married: @wife-e5e5e5, 1975\nPartner: @second-f6f6f6\n',
    ),
    ('older-g7g7g7', 'Name: Older\nBorn: 1945\nParents: @dad-b2b2b2\n'),
    ('younger-h8h8h8', 'Name: Younger\nBorn: 1955\nParents: @dad-b2b2b2\n'),
    ('wife-e5e5e5', 'Name: Wife\n'),
    ('second-f6f6f6', 'Name: Second\n'),
    (
      'kid-i9i9i9',
      'Name: Kid\nParents: @me-d4d4d4, @wife-e5e5e5\nPartner: @in-law-j1j1j1\n',
    ),
    ('later-k2k2k2', 'Name: Later\nParents: @me-d4d4d4, @second-f6f6f6\n'),
    ('lone-l3l3l3', 'Name: Lone\nParents: @me-d4d4d4\n'),
    ('in-law-j1j1j1', 'Name: In Law\n'),
    ('grandkid-m4m4m4', 'Name: Grandkid\nParents: @kid-i9i9i9\n'),
  ]) {
    final p = Person.fromSource('p-${dir.split('-').last}', dir, source);
    tree.people[p.id] = p;
  }
  final index = Index.build(tree);
  final me = tree.people['p-d4d4d4']!;

  test('parents father first, with their parents', () {
    final h = Hourglass.of(me, tree, index);
    expect(h.parents.map((p) => p.id), ['p-b2b2b2', 'p-c3c3c3']);
    expect(h.parents.first.parents, ['p-a1a1a1']);
    expect(h.parents.last.parents, isEmpty);
  });

  test('brothers and sisters either side by birth', () {
    final h = Hourglass.of(me, tree, index);
    expect(h.older, ['p-g7g7g7']);
    expect(h.younger, ['p-h8h8h8']);
  });

  test('children grouped by their other parent', () {
    final h = Hourglass.of(me, tree, index);
    expect(h.partners, ['p-e5e5e5', 'p-f6f6f6']);
    expect(
      [
        for (final g in h.children)
          '${g.other}: ${g.children.map((c) => c.id).join(', ')}',
      ],
      ['p-e5e5e5: p-i9i9i9', 'p-f6f6f6: p-k2k2k2', 'null: p-l3l3l3'],
    );
    final kid = h.children.first.children.single;
    expect(kid.partners, ['p-j1j1j1']);
    expect(kid.children, ['p-m4m4m4']);
    expect(h.size, 11);
  });

  test('the busiest chart is the default', () {
    expect(Hourglass.busiest(tree, index)?.id, me.id);
  });
}
