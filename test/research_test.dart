import 'package:prosapia/src/file_store.dart';
import 'package:prosapia/src/research.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

/// A small tree: a couple, their daughter, and a census item naming them.
Tree _tree() {
  final tree = Tree('test');
  void add(String directory, String source) {
    final id = 'p-${directory.split('-').last}';
    tree.people[id] = Person.fromSource(id, directory, source);
  }

  add('carew-michael-k3m9qa', '''
Name: Michael Carew
Born: about 1853, New York, source: #census-1860-c4n5us
Born: 1854, source: needed
Christened:
Married: @nolan-kathleen-a1b2c3, 1881
Occupation: Carpenter
FamilySearch: LZ5X-QRT

He worked for the parks [source: ?].
''');
  add('nolan-kathleen-a1b2c3', '''
Name: Kathleen Nolan
Also known as: Catharine A. Carew (married name)
Born: about 1858
Died: 28 September 1898, Bronx, source: #m-d3a7h1
''');
  add('carew-alma-z9y8x7', '''
Name: Alma Carew
Born: 1890
Parents: @carew-michael-k3m9qa, @nolan-kathleen-a1b2c3, Ann Somebody

Her father was @carew-michael-k3m9qa.
''');
  tree.media['m-c4n5us'] =
      Media('m-c4n5us', isBack: false, extension: 'jpg', location: '')
        ..title = '1860 census, Carew household'
        ..link = 'https://example.com/ark'
        ..people.add('p-k3m9qa');
  tree.media['m-d3a7h1'] =
      Media('m-d3a7h1', isBack: false, extension: '', location: '')
        ..title = 'Death of Catharine A. Carew'
        ..people.add('p-a1b2c3');
  return tree;
}

/// The [key] of each map in [list].
List<Object?> _each(Object? list, [String key = 'id']) => [
  for (final m in (list as List).cast<Map<String, Object?>>()) m[key],
];

void main() {
  final research = Research(_tree());

  group('pageOf', () {
    test('takes an id or a reference in any form', () {
      for (final r in [
        'carew-michael-k3m9qa',
        '@carew-michael-k3m9qa',
        'p-k3m9qa',
        'k3m9qa',
      ]) {
        expect(research.pageOf(r)?.id, 'p-k3m9qa', reason: r);
      }
      expect(research.pageOf('nobody-zzzzzz'), isNull);
    });
  });

  group('show', () {
    final shown = research.show(research.pageOf('p-k3m9qa')!);

    test('gives the text, facts and sources as read', () {
      expect(shown['source'], startsWith('Name: Michael Carew'));
      final facts = shown['facts'] as List;
      expect(facts.first, {'label': 'Name', 'value': 'Michael Carew'});
      expect((facts[1] as Map)['sources'], ['#census-1860-c4n5us']);
      final born = (shown['events'] as Map)['born'] as Map;
      expect(born['place'], 'New York');
      expect(
        (born['alsoRecorded'] as List).single,
        containsPair('date', '1854'),
      );
      expect(shown['externalIds'], {'FamilySearch': 'LZ5X-QRT'});
    });

    test('gives the family, from whichever page states it', () {
      final family = shown['family'] as Map;
      expect(_each(family['partners']), ['p-a1b2c3']);
      expect(_each(family['children']), ['p-z9y8x7']);
    });

    test('lists the items that show or are cited, and who mentions them', () {
      expect(_each(shown['items'], 'reference'), ['#m-c4n5us']);
      expect((shown['items'] as List).single, containsPair('link', isNotNull));
      expect(shown['mentionedOn'], [
        {'id': 'p-z9y8x7', 'title': 'Alma Carew'},
      ]);
    });

    test('names relatives who have no page', () {
      final alma = research.show(research.pageOf('p-z9y8x7')!);
      expect((alma['family'] as Map)['namedParents'], ['Ann Somebody']);
    });
  });

  group('gaps', () {
    test('lists empty, unsourced and wanted facts', () {
      final gaps = research.gaps(research.pageOf('p-k3m9qa')! as Person);
      expect(gaps['empty'], ['Christened']);
      expect(gaps['missing'], ['Died', 'Parents']);
      expect(gaps['unsourced'], [
        'Married: Kathleen Nolan, 1881',
        'Occupation: Carpenter',
      ]);
      expect(gaps['wanted'], ['Born', 'Story']);
    });

    test('a sourced page has nothing unsourced', () {
      final gaps = research.gaps(research.pageOf('p-a1b2c3')! as Person);
      expect(gaps['unsourced'], ['Born: about 1858']);
      expect(gaps['missing'], ['Parents']);
    });
  });

  group('find', () {
    test('matches every word as the start of a name, any name known by', () {
      expect(_each(research.find('carew')), hasLength(3));
      expect(_each(research.find('cath carew')), ['p-a1b2c3']);
      expect(research.find('mich nolan'), isEmpty);
    });

    test('narrows by birth year and place', () {
      expect(_each(research.find('carew', born: 1890)), ['p-z9y8x7']);
      expect(_each(research.find('carew', place: 'york')), ['p-k3m9qa']);
    });
  });

  test('reads a tree of files', () async {
    final tree = await FileStore('test/fixtures/tree').load();
    final found = Research(tree).find('hughes', born: 1887);
    expect(found.single['name'], 'Margaret Ellen Hughes');
    expect(found.single['parents'], ['Thomas Hughes', 'Ann Price']);
  });
}
