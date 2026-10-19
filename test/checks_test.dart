import 'package:prosapia/src/index.dart';
import 'package:prosapia/src/render.dart';
import 'package:prosapia/src/store.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  Renderer renderer(Map<String, String> pages) {
    final tree = Tree('test');
    pages.forEach((directory, source) {
      final id = 'p-${directory.split('-').last}';
      tree.people[id] = Person.fromSource(id, directory, source);
    });
    return Renderer(tree, Index.build(tree));
  }

  test('implausible dates become questions', () {
    final r = renderer({
      'parent-aaaaaa': 'Name: Parent\nBorn: 1900\nDied: 1940',
      'child-bbbbbb':
          'Name: Child\nBorn: 1950\nDied: 1940\nParents: @parent-aaaaaa\n'
          'Married: Someone, 1955',
    });
    final checks = r.checksOf(r.tree.people['p-bbbbbb']!);
    expect(checks, hasLength(4));
    expect(checks.join(' '), contains('Died in 1940, before being born'));
    expect(checks.join(' '), contains('after Parent died in 1940'));
    expect(checks.join(' '), contains('at about 5'));
    expect(checks.join(' '), contains('after dying in 1940'));
  });

  test('a marriage after a death', () {
    final r = renderer({
      'a-aaaaaa': 'Name: A\nBorn: 1900\nDied: 1940\nMarried: @b-bbbbbb, 1950',
      'b-bbbbbb': 'Name: B\nBorn: 1905\nDied: 1945',
    });
    final checks = r.checksOf(r.tree.people['p-aaaaaa']!);
    expect(checks, [
      'Married in 1950, after dying in 1940.',
      'Married B in 1950, after B died in 1945.',
    ]);
    expect(r.correctionCount(), greaterThanOrEqualTo(2));
  });

  test('ordinary lives raise nothing', () {
    final r = renderer({
      'parent-aaaaaa': 'Name: Parent\nBorn: 1900\nDied: 1980',
      'child-bbbbbb': 'Name: Child\nBorn: about 1930\nParents: @parent-aaaaaa',
    });
    expect(r.checksOf(r.tree.people['p-bbbbbb']!), isEmpty);
  });

  test('a parent stated on the parent page counts for the child', () {
    final r = renderer({
      'parent-aaaaaa': 'Name: Parent\nChildren: @child-bbbbbb',
      'child-bbbbbb': 'Name: Child',
    });
    expect(r.index.parentsOf('p-bbbbbb'), ['p-aaaaaa']);
    expect(r.index.childrenOf('p-aaaaaa'), ['p-bbbbbb']);
  });

  test('siblings are offered to be recorded through their parents', () {
    final tree = Tree('test');
    for (final (dir, source) in [
      ('a-aaaaaa', 'Name: A\nSiblings: @b-bbbbbb, @c-cccccc, @d-dddddd\n'),
      ('b-bbbbbb', 'Name: B\nParents: @p-pppppp\n'),
      ('c-cccccc', 'Name: C\n'),
      ('d-dddddd', 'Name: D\nParents: @p-pppppp\n'),
      ('p-pppppp', 'Name: P\n'),
    ]) {
      final id = 'p-${dir.split('-').last}';
      tree.people[id] = Person.fromSource(id, dir, source);
    }
    final r = Renderer(
      tree,
      Index.build(tree),
      viewer: Member('a@example.com', Role.editor),
      editable: true,
    );
    final html = r.personArticle(tree.people['p-aaaaaa']!);
    expect(html, contains('Record P as A&#39;s parents instead'));
    expect(html, isNot(contains('as C&#39;s parents')));
  });
}
