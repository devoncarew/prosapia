import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  test(
    'the editor understands the offered labels and their other spellings',
    () {
      final understood = Person.understoodLabels;
      for (final label in Person.labels) {
        expect(understood, contains(label.toLowerCase()));
      }
      expect(understood, containsAll(['baptized', 'spouse', 'findagrave']));
      expect(understood, isNot(contains('divored')));
      expect(understood, isNot(contains('note')));
    },
  );

  test('ids in other systems are read with or without "ID"', () {
    final p = Person.fromSource(
      'p-a1a1a1',
      'carew-john-a1a1a1',
      'Name: John Carew\nFamilySearch ID: LZ5X-QRT\nWikiTree: Carew-123\n'
          'Find a Grave ID: 12345678\nFamilySearch ID: MTZQ-Q43\n',
    );
    expect(p.externalIds, {
      'FamilySearch': ['LZ5X-QRT', 'MTZQ-Q43'],
      'WikiTree': ['Carew-123'],
      'Find a Grave': ['12345678'],
    });
    expect(p.facts, isEmpty);
  });

  test('ids in file metadata use the project prefix', () {
    expect(Media.idScheme, 'prosapia:');
  });

  test('media file names give the id and the side', () {
    expect(Media.namePattern.firstMatch('m-5t1q8z.jpg')![2], isNull);
    expect(Media.namePattern.firstMatch('m-5t1q8z-back.jpg')![2], '-back');
    expect(Media.namePattern.firstMatch('notes.txt'), isNull);
  });

  test('an item without a file keeps its link and when it was found', () {
    final item = Media('m-a1b2c3', isBack: false, extension: '', location: '')
      ..title = 'Obituary'
      ..link = 'https://example.com/obituary'
      ..found = '19 October 2026';
    expect(item.hasFile, isFalse);
    expect(item.kind, 'source');
    final again = Media.fromMap(item.toMap());
    expect(again.link, item.link);
    expect(again.found, item.found);
    expect(again.hasFile, isFalse);
  });
}
