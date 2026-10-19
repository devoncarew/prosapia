import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
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
