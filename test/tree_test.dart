import 'package:prosapia/src/page_source.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  test('a person file splits into structured facts and prose', () {
    final (yaml, body) = splitFrontMatter('''
---
id: p-7k2m9x
name: Margaret Ellen Hughes
born:
  date: 1887
parents:
  - id: p-3f8d1a
    relationship: adopted
  - p-9c4e2b
---

Margaret grew up above the store.
''');
    final person = Person.fromMap(yaml, body, 'hughes-margaret-ellen-7k2m9x');
    expect(person.name, 'Margaret Ellen Hughes');
    expect(person.born!.date!.year, 1887, reason: 'a bare year is read as text');
    expect(person.parents.map((l) => l.id), ['p-3f8d1a', 'p-9c4e2b']);
    expect(person.parents.first.relationship, 'adopted');
    expect(person.years, 'born 1887');
    expect(person.body, 'Margaret grew up above the store.');
  });

  test('a person survives a round trip through its structured fields', () {
    final fields = {
      'id': 'p-7k2m9x',
      'name': 'Margaret Ellen Hughes',
      'surname': 'Hughes',
      'born': {'date': '1887-03-14', 'place': 'Scranton', 'coordinates': [41.4, -75.6]},
      'parents': [
        {'id': 'p-3f8d1a', 'relationship': 'adopted'},
        'p-9c4e2b',
      ],
      'facts': [
        {'type': 'occupation', 'value': 'Teacher', 'date': 'ABT 1910'},
      ],
      'gedcom_id': 'I5',
    };
    expect(Person.fromMap(fields, '', 'dir').toMap(), fields);
  });

  test('a file without front matter is rejected', () {
    expect(() => splitFrontMatter('just prose'), throwsFormatException);
  });

  test('ids in file metadata use the project prefix', () {
    expect(Media.idScheme, 'prosapia:');
  });

  test('media file names give the id and the side', () {
    expect(Media.namePattern.firstMatch('m-5t1q8z.jpg')![2], isNull);
    expect(Media.namePattern.firstMatch('m-5t1q8z-back.jpg')![2], '-back');
    expect(Media.namePattern.firstMatch('notes.txt'), isNull);
  });
}
