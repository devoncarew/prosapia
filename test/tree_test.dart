import 'package:loom/src/tree.dart';
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
    final person = Person.fromYaml(yaml, body, 'hughes-margaret-ellen-7k2m9x');
    expect(person.name, 'Margaret Ellen Hughes');
    expect(person.born!.date!.year, 1887, reason: 'a bare year is read as text');
    expect(person.parents.map((l) => l.id), ['p-3f8d1a', 'p-9c4e2b']);
    expect(person.parents.first.relationship, 'adopted');
    expect(person.years, 'born 1887');
    expect(person.body, 'Margaret grew up above the store.');
  });

  test('a file without front matter is rejected', () {
    expect(() => splitFrontMatter('just prose'), throwsFormatException);
  });

  test('media file names give the id and the side', () {
    expect(Media.idPattern.firstMatch('m-5t1q8z.jpg')![2], isNull);
    expect(Media.idPattern.firstMatch('m-5t1q8z-back.jpg')![2], '-back');
    expect(Media.idPattern.firstMatch('notes.txt'), isNull);
  });
}
