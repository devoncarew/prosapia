import 'package:prosapia/src/gather.dart';
import 'package:prosapia/src/index.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  final tree = Tree('test');
  for (final (dir, source) in [
    (
      'davidson-allan-maclean-a1a1a1',
      'Name: Allan MacLean Davidson\nNickname: Scotty\nBorn: 1890\n'
          'Children: @davidson-ann-b2b2b2\n\nHe farmed.\n',
    ),
    (
      'davidson-ann-b2b2b2',
      'Name: Ann Davidson\nBorn: 1920, Sherbrooke\nOccupation: nurse\n\n'
          'Her father @davidson-allan-maclean-a1a1a1 drove her to school.\n\n'
          'She had a dog.\n',
    ),
    (
      'smith-joe-c3c3c3',
      'Name: Joe Smith\n\nJoe worked with Scotty Davidson at the mill.\n',
    ),
  ]) {
    final p = Person.fromSource('p-${dir.split('-').last}', dir, source);
    tree.people[p.id] = p;
  }
  final index = Index.build(tree);
  final allan = tree.people['p-a1a1a1']!;

  test('linked mentions, then names, then relatives', () {
    final found = elsewhere(allan, tree, index);
    expect(found.map((e) => (e.from, e.byName)), [
      ("Ann Davidson's page", false),
      ("Joe Smith's page", true),
      ("Ann Davidson's facts (Allan MacLean Davidson's child)", false),
    ]);
    expect(found.first.text, contains('drove her to school'));
    expect(found.first.text, isNot(contains('dog')));
    expect(found.last.text, 'Born: 1920, Sherbrooke\nOccupation: nurse');
  });

  test('stops at the budget', () {
    expect(elsewhere(allan, tree, index, budget: 60), hasLength(1));
  });
}
