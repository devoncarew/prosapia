import 'package:loom/src/diff.dart';
import 'package:loom/src/page_source.dart';
import 'package:loom/src/tree.dart';
import 'package:test/test.dart';

const source = '''
---
id: p-7k2m9x
name: Margaret Ellen Hughes
surname: Hughes
also_known_as: [Peg, "Maggie, the younger"]
born:
  date: 1887-03-14
  place: "Scranton, Pennsylvania"
  coordinates: [41.4, -75.6]
died:
  date: ABT 1961
parents:
  - id: p-3f8d1a
    relationship: adopted
  - p-9c4e2b
facts:
  - type: occupation
    value: "Teacher: Latin & Greek"
    date: BET 1908 AND 1920
  - type: title
    value: "1958"
gedcom_id: I5
---

Margaret grew up above the store.

## 1923: Trip to Wales

She sailed in June.
''';

void main() {
  Person parse(String text) => parsePersonSource(text, id: 'p-7k2m9x', directory: 'hughes-margaret-ellen-7k2m9x');

  test('page text survives being read and written back', () {
    expect(personSource(parse(source)), source.trimLeft());
  });

  test('values that look like numbers stay text', () {
    final person = parse(source);
    expect(person.facts.last.value, '1958');
    expect(person.born!.date!.raw, '1887-03-14');
    expect(parse(personSource(person)).facts.last.value, '1958');
  });

  test('a page with no story is just its facts', () {
    final person = parse('---\nid: p-7k2m9x\nname: Margaret\n---');
    expect(person.body, '');
    expect(personSource(person), '---\nid: p-7k2m9x\nname: Margaret\n---\n');
  });

  test('mistakes are explained to the person editing', () {
    expect(() => parse('Margaret grew up above the store.'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('three dashes'))));
    expect(() => parse('---\nid: p-other\nname: Margaret\n---\n'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('id must stay'))));
    expect(() => parse('---\nid: p-7k2m9x\n---\n'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('needs a name'))));
    expect(() => parse('---\nid: p-7k2m9x\nname: [unclosed\n---\n'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('could not be read'))));
    expect(() => parse('---\nid: p-7k2m9x\nname: Margaret\nparents: 7\n---\n'), throwsFormatException);
  });

  test('a comparison marks only the lines that changed', () {
    final lines = diffLines('one\ntwo\nthree', 'one\n2\nthree\nfour');
    expect(lines.map((l) => '${l.kind.name}:${l.text}'),
        ['same:one', 'removed:two', 'added:2', 'same:three', 'added:four']);
  });
}
