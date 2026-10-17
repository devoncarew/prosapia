import 'package:prosapia/src/staging.dart';
import 'package:test/test.dart';

void main() {
  test('files are recognised by their first bytes', () {
    expect(Staging.kindOf([0xff, 0xd8, 0xff, 0xe0]), 'jpg');
    expect(Staging.kindOf('%PDF-1.7\n'.codeUnits), 'pdf');
    expect(Staging.kindOf([0x89, 0x50, 0x4e, 0x47, 0x0d]), 'png');
    expect(Staging.kindOf('PK\x03\x04'.codeUnits), isNull);
    expect(Staging.kindOf('%PD'.codeUnits), isNull);
  });
}
