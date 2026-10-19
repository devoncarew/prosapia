import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

const howard = '''
Name: Howard Joseph Carew
Also known as: Howie
Sex: male
Born: 6 January 1911, Brooklyn, NY, USA
Died: November 1987
Buried: St. John's Episcopal Church, York, PA
Parents: @carew-joseph-j-brq52d, @howard-irene-genevive-4dd34j (adopted)
Married: @dwyer-frances-davidson-kyzwpd, 7 January 1945, Trinity Episcopal Church, Hartford, CT
Children: @carew-susan-irene-abc123, Mary Ducker
Occupation: Founder & President, Carew Corporation, 1946 to 1987
Residence: 1950, [place: York, PA]
Note: Died perhaps 23 years old of TB
Hobby: golf

Howard went to Princeton with @smith-john-zzz999.

## 1934: Sailing to Africa
''';

void main() {
  final p = Person.fromSource('p-tbczm8', 'carew-howard-joseph-tbczm8', howard);

  test('the page is kept exactly as written', () {
    expect(p.source, howard);
  });

  test('identity and life events', () {
    expect(p.name, 'Howard Joseph Carew');
    expect(p.alsoKnownAs, ['Howie']);
    expect(p.born!.date!.meaning, '6 January 1911');
    expect(p.born!.place, 'Brooklyn, NY, USA');
    expect(p.died!.date!.year, 1987);
    expect(p.died!.place, isNull);
    expect(p.buried!.date, isNull);
    expect(p.buried!.place, "St. John's Episcopal Church, York, PA");
    expect(p.years, '1911–1987');
  });

  test('relationships', () {
    expect(p.parents.map((r) => r.id), ['p-brq52d', 'p-4dd34j']);
    expect(p.parents.last.qualifier, 'adopted');
    expect(p.children.first.id, 'p-abc123');
    expect(p.children.last.id, isNull);
    expect(p.children.last.name, 'Mary Ducker');
    final married = p.couples.single;
    expect(married.partner!.id, 'p-kyzwpd');
    expect(married.event.date!.year, 1945);
    expect(married.event.place, 'Trinity Episcopal Church, Hartford, CT');
  });

  test('a name may have a number or a suffix', () {
    final q = Person.fromSource(
      'p-0',
      'x-0',
      'Name: Q\nChildren: June Wilhelm, "Rudie Wilhelm 3rd", 1920\n',
    );
    expect(q.children.map((c) => c.name), [
      'June Wilhelm',
      'Rudie Wilhelm 3rd',
    ]);
    expect(q.issues.single, contains('"1920" is not a person'));
    expect(nameParts('Rudolph H. Wilhelm Jr.').surname, 'Wilhelm');
    expect(nameParts('Rudie Wilhelm 3rd').suffix, ['3rd']);
    expect(nameParts('Cher').surname, isNull);
  });

  test('empty facts say nothing, and are not problems', () {
    final q = Person.fromSource(
      'p-0',
      'x-0',
      'Name: Q\nSex:\nBorn:\nDied:\nParents:\nNote:\n',
    );
    expect(q.issues, isEmpty);
    expect(q.born, isNull);
    expect(q.notes, isEmpty);
    expect(q.sexValue, 'unknown');
  });

  test('a fact the records disagree on is also recorded', () {
    final q = Person.fromSource(
      'p-0',
      'x-0',
      'Name: Q\nBorn: 1911, source: 1920 census\n'
          'Born: 1912, source: birth certificate\n',
    );
    expect(q.born?.date?.year, 1911);
    expect(q.alternativesTo(q.born).single.date?.year, 1912);
    expect(q.issues, isEmpty);
  });

  test('family name and kinds of name', () {
    final q = Person.fromSource(
      'p-0',
      'x-0',
      'Name: Maria de la Cruz García\nFamily name: de la Cruz\n'
          'Also known as: Maria Price (married name)\n',
    );
    expect(q.surname, 'de la Cruz');
    expect(q.alsoKnownAs, ['Maria Price']);
    expect(q.nameKinds['Maria Price'], 'married name');
  });

  test('a date that cannot be read is reported, not taken for a place', () {
    final q = Person.fromSource(
      'p-0',
      'x-0',
      'Name: Q\nBorn: "New York, NY", between 1861\n',
    );
    expect(q.born?.place, 'New York, NY');
    expect(q.born?.date?.raw, 'between 1861');
    expect(q.issues.single, contains('not a date Prosapia can read'));
  });

  test('a date may follow the place', () {
    final q = Person.fromSource(
      'p-0',
      'x-0',
      'Name: Q\nBorn: "Portland, Oregon", "18 March 1914"\n'
          'Buried: River View Cemetery, "Portland, Oregon"\n',
    );
    expect(q.born?.place, 'Portland, Oregon');
    expect(q.born?.date?.year, 1914);
    expect(q.buried?.place, 'River View Cemetery, Portland, Oregon');
    expect(q.buried?.date, isNull);
  });

  test('other facts read as what, when, where', () {
    final job = p.facts.firstWhere((f) => f.label == 'Occupation');
    expect(job.description, 'Founder & President, Carew Corporation');
    expect(job.event.date!.raw, '1946 to 1987');
    expect(job.event.place, isNull, reason: 'a place must be marked');
    final home = p.facts.firstWhere((f) => f.label == 'Residence');
    expect(home.event.date!.year, 1950);
    expect(home.event.place, 'York, PA');
    expect(
      p.facts.any((f) => f.label == 'Hobby' && f.description == 'golf'),
      isTrue,
    );
    expect(p.notes.single, 'Died perhaps 23 years old of TB');
  });

  test('the story follows the facts', () {
    expect(p.body, startsWith('Howard went to Princeton'));
  });

  test('what cannot be read is reported, never rejected', () {
    final odd = Person.fromSource('p-1', 'x-1', '''
Name: Ann
this line has no label
Partner: @price-owen-4h8w2r, married 1945
Born: [date: someday]

Prose.''');
    expect(odd.name, 'Ann');
    expect(odd.partners.single.id, 'p-4h8w2r');
    expect(odd.issues, hasLength(3));
    expect(odd.issues.join(' '), contains('Married:'));
    expect(odd.body, 'Prose.');
  });

  test('a page without a Name line is all prose', () {
    final prose = Person.fromSource('p-1', 'x-1', 'Note: this is prose.');
    expect(prose.body, 'Note: this is prose.');
    expect(prose.issues.single, contains('Name:'));
  });

  test('a nickname is shown after the given name', () {
    final scotty = Person.fromSource(
      'p-1',
      'x-1',
      'Name: Allan MacLean Davidson\nNickname: Scotty\nAlso known as: A. M. Davidson\n',
    );
    expect(scotty.nicknames, ['Scotty']);
    expect(scotty.alsoKnownAs, ['A. M. Davidson']);
    expect(scotty.displayName, 'Allan “Scotty” MacLean Davidson');
    expect(p.displayName, 'Howard Joseph Carew');
  });

  group('parts of a fact', () {
    Person read(String facts) =>
        Person.fromSource('p-1', 'x-1', 'Name: A\n$facts\n');

    test('a quoted value keeps its commas; a part can be labelled', () {
      final p = read('Born: "January 6, 1990", place: "Portland, OR"');
      expect(p.born!.date!.raw, 'January 6, 1990');
      expect(p.born!.date!.understood, isTrue);
      expect(p.born!.place, 'Portland, OR');
      expect(p.issues, isEmpty);
    });

    test('an unquoted date with a comma is still read whole', () {
      final p = read('Born: January 6, 1911, Brooklyn, NY');
      expect(p.born!.date!.raw, 'January 6, 1911');
      expect(p.born!.place, 'Brooklyn, NY');
    });

    test('the partner is found anywhere, and a source is kept', () {
      final p = read(
        'Married: 4 August 1910, @howard-irene-4dd34j, '
        'place: "Brooklyn, New York City, New York",\n'
        '  source: "New York, New York City Marriage Records, 1829-1938"',
      );
      final c = p.couples.single;
      expect(c.partner!.id, 'p-4dd34j');
      expect(c.event.date!.raw, '4 August 1910');
      expect(c.event.place, 'Brooklyn, New York City, New York');
      expect(c.event.sources, [
        'New York, New York City Marriage Records, 1829-1938',
      ]);
      expect(p.issues, isEmpty);
    });

    test('a named partner, wherever it is', () {
      final p = read('Married: 1884, Ann Price, place: "Hartford, CT"');
      expect(p.couples.single.partner!.name, 'Ann Price');
      expect(p.couples.single.event.place, 'Hartford, CT');
    });

    test('quotes inside a value are doubled', () {
      final p = read('Occupation: "Editor, ""The Courant""", 1920');
      expect(p.facts.single.description, 'Editor, "The Courant"');
      expect(p.facts.single.event.date!.raw, '1920');
    });

    test('a quoted name with a comma is one person', () {
      final p = read('Children: "Margaret Hughes, Jr.", @hughes-mary-x2k9ab');
      expect(p.children.map((r) => r.name ?? r.id), [
        'Margaret Hughes, Jr.',
        'p-x2k9ab',
      ]);
    });
  });
}
