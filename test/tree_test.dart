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
}
