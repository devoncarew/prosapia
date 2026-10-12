import 'package:loom/src/dates.dart';
import 'package:test/test.dart';

void main() {
  test('exact dates display in words', () {
    expect(LoomDate('1950-05-17').display, '17 May 1950');
    expect(LoomDate('1987-11').display, 'Nov 1987');
    expect(LoomDate('1972').display, '1972');
  });

  test('qualified dates and ranges display in words', () {
    expect(LoomDate('ABT 1961').display, 'about 1961');
    expect(LoomDate('BEF 1850').display, 'before 1850');
    expect(LoomDate('BET 1946 AND 1987').display, '1946–1987');
    expect(LoomDate('BET 7 AUG 1941 AND 27 SEP 1946').display, '7 Aug 1941–27 Sep 1946');
    // Not valid GEDCOM, but it occurs in real exports.
    expect(LoomDate('BET FEB AND JUL 1934').display, 'Feb–Jul 1934');
  });

  test('dates sort by their earliest point', () {
    final dates = ['1950-05-17', 'BET 1946 AND 1987', '1911-01-06', 'ABT 1930', '1987-11']
        .map(LoomDate.new)
        .toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    expect(dates.map((d) => d.raw),
        ['1911-01-06', 'ABT 1930', 'BET 1946 AND 1987', '1950-05-17', '1987-11']);
  });

  test('year is the first year mentioned', () {
    expect(LoomDate('BET 1946 AND 1987').year, 1946);
    expect(LoomDate('unknown').year, isNull);
  });
}
