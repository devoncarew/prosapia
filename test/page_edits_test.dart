import 'package:prosapia/src/contradictions.dart';
import 'package:prosapia/src/page_edits.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  const thomas = '''
Name: Thomas Hughes
Born: 1852
Married: Ann Price, 1884
Children: @hughes-margaret-ellen-7k2m9x, Mary Hughes (adopted), David Hughes

Thomas kept a hardware store. His daughter @hughes-margaret-ellen-7k2m9x
taught school.
''';

  group('nameToReference', () {
    test('replaces a plain name and keeps its qualifier', () {
      final out = nameToReference(
        thomas,
        'children',
        'mary  hughes',
        '@hughes-mary-x2k9ab',
      );
      expect(
        out,
        contains(
          'Children: @hughes-margaret-ellen-7k2m9x, '
          '@hughes-mary-x2k9ab (adopted), David Hughes\n',
        ),
      );
      // Everything else is left exactly as written.
      expect(
        out!.replaceFirst(
          '@hughes-mary-x2k9ab (adopted), David Hughes',
          'Mary Hughes (adopted), David Hughes',
        ),
        thomas,
      );
    });

    test('names the partner of a two-person event', () {
      expect(
        nameToReference(thomas, 'married', 'Ann Price', '@price-ann-9c4e2b'),
        contains('Married: @price-ann-9c4e2b, 1884\n'),
      );
    });

    test('returns null when the name is not in such a line', () {
      expect(nameToReference(thomas, 'parents', 'David Hughes', '@x'), isNull);
      expect(nameToReference(thomas, 'children', 'Ann Price', '@x'), isNull);
    });
  });

  group('removeRelation', () {
    test('removes a reference, and the line once it is empty', () {
      final out = removeRelation(thomas, 'children', 'p-7k2m9x')!;
      expect(out, contains('Children: Mary Hughes (adopted), David Hughes\n'));
      const single = 'Name: A\nParents: @b-c-123456\nBorn: 1900\n';
      expect(
        removeRelation(single, 'parents', 'p-123456'),
        'Name: A\nBorn: 1900\n',
      );
    });

    test('removes a whole marriage line', () {
      const page = 'Name: A\nMarried: @b-123456, 1945, Hartford\n\nText.\n';
      expect(removeRelation(page, 'married', 'p-123456'), 'Name: A\n\nText.\n');
    });
  });

  test('references become plain names when a page is deleted', () {
    final out = referencesToName(thomas, 'p-7k2m9x', 'Margaret Hughes, Jr.');
    expect(out, contains('Children: Margaret Hughes Jr., Mary Hughes'));
    expect(out, contains('His daughter Margaret Hughes Jr.\n'));
    expect(mentions(thomas, 'p-7k2m9x'), isTrue);
    expect(mentions(out, 'p-7k2m9x'), isFalse);
  });

  test('a relationship stated only on a deleted page is kept as a name', () {
    final madej = Person.fromSource(
      'p-7nm4er',
      'madej-something-7nm4er',
      'Name: Something Madej\nPartner: @dwyer-lisa-fxb7e3\n'
          'Married: @dwyer-lisa-fxb7e3, 1990, Hartford\n'
          'Children: @madej-ann-a1b2c3 (adopted)\n',
    );
    expect(
      keepRelations(
        'Name: Lisa Dwyer\nPartner: @x-111111\n\nText.\n',
        madej,
        'p-fxb7e3',
      ),
      'Name: Lisa Dwyer\nPartner: @x-111111, Something Madej\n'
      'Married: Something Madej, 1990, Hartford\n\nText.\n',
    );
    expect(
      keepRelations('Name: Ann Madej\n', madej, 'p-a1b2c3'),
      'Name: Ann Madej\nParents: Something Madej (adopted)\n',
    );
    // A page that names them itself is handled by referencesToName.
    expect(
      keepRelations('Name: Lisa\nPartner: @madej-7nm4er\n', madej, 'p-fxb7e3'),
      isNull,
    );
    expect(keepRelations('Name: Someone else\n', madej, 'p-999999'), isNull);
  });

  test('new pages and their directories', () {
    expect(
      newPage(
        name: 'Mary Hughes ',
        born: 'about 1890',
        parents: ['@hughes-thomas-3f8d1a'],
      ),
      'Name: Mary Hughes\nBorn: about 1890\nParents: @hughes-thomas-3f8d1a\n',
    );
    expect(
      directoryFor('Mary Ellen Hughes', 'p-x2k9ab'),
      'hughes-mary-ellen-x2k9ab',
    );
    expect(directoryFor('Zoë', 'p-x2k9ab'), 'zo-x2k9ab');
    expect(
      directoryFor('Rudolph H. Wilhelm Jr.', 'p-7z4nh6'),
      'wilhelm-rudolph-h-jr-7z4nh6',
    );
    expect(directoryFor('', 'p-x2k9ab'), 'x2k9ab');
  });

  group('contradictions', () {
    Tree tree(Map<String, String> pages) {
      final t = Tree('test');
      pages.forEach((dir, source) {
        final p = Person.fromSource('p-${dir.split('-').last}', dir, source);
        t.people[p.id] = p;
      });
      return t;
    }

    test('agreeing pages are not a contradiction', () {
      final t = tree({
        'a-111111': 'Name: A\nChildren: @b-222222\nMarried: @c-333333, 1945\n',
        'b-222222': 'Name: B\nParents: @a-111111, @c-333333\n',
        'c-333333': 'Name: C\nMarried: @a-111111, 1945\n',
      });
      for (final p in t.people.values) {
        expect(contradictionsOf(t, p), isEmpty, reason: p.name);
      }
    });

    test('a parent who is also a child', () {
      final t = tree({
        'a-111111': 'Name: A\nChildren: @b-222222\n',
        'b-222222': 'Name: B\nChildren: @a-111111\n',
      });
      final found = contradictionsOf(t, t.people['p-111111']!);
      expect(
        found.single.message,
        "B is listed as both A's child and A's parent.",
      );
      expect(found.single.statements.map((s) => s.page), [
        'p-111111',
        'p-222222',
      ]);
    });

    test('marriages recorded differently on the two pages', () {
      final t = tree({
        'a-111111': 'Name: A\nMarried: @c-333333, 1945\n',
        'c-333333': 'Name: C\nMarried: @a-111111, 1946\n',
      });
      final found = contradictionsOf(t, t.people['p-111111']!);
      expect(found.single.message, contains('1945 on A\'s page, 1946 on C\'s'));
    });

    test('listing oneself', () {
      final t = tree({'a-111111': 'Name: A\nSiblings: @a-111111\n'});
      expect(
        contradictionsOf(t, t.people['p-111111']!).single.message,
        'A is listed as their own sibling.',
      );
    });
  });

  test('a relative is added to a relationship line, or a new one', () {
    const page = 'Name: A\nParents: @b-b1b1b1\n\nStory.\n';
    expect(
      addRelation(page, 'parents', '@c-c2c2c2'),
      'Name: A\nParents: @b-b1b1b1, @c-c2c2c2\n\nStory.\n',
    );
    expect(
      addRelation(page, 'partner', '@d-d3d3d3'),
      'Name: A\nParents: @b-b1b1b1\nPartner: @d-d3d3d3\n\nStory.\n',
    );
    expect(
      addFact(page, 'Married', '@d-d3d3d3, 1945'),
      'Name: A\nParents: @b-b1b1b1\nMarried: @d-d3d3d3, 1945\n\nStory.\n',
    );
  });
}
