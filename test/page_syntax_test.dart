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
}
