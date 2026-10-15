import 'package:prosapia/src/dates.dart';
import 'package:test/test.dart';

void main() {
  String meaning(String text) => TreeDate.parse(text).meaning;

  test('a date is kept exactly as typed', () {
    expect(TreeDate.parse('spring  of 1925').display, 'spring  of 1925');
  });

  test('the common ways of writing a date are understood', () {
    expect(meaning('14 March 1887'), '14 March 1887');
    expect(meaning('14 MAR 1887'), '14 March 1887');
    expect(meaning('March 14, 1887'), '14 March 1887');
    expect(meaning('1887-03-14'), '14 March 1887');
    expect(meaning('Mar 1887'), 'March 1887');
    expect(meaning('1887'), '1887');
    expect(meaning('3/14/1887'), '14 March 1887');
  });

  test('uncertain dates', () {
    expect(meaning('about 1925'), 'about 1925');
    expect(meaning('abt. 1925'), 'about 1925');
    expect(meaning('c. 1925'), 'about 1925');
    expect(meaning('ABT 1961'), 'about 1961');
    expect(meaning('before 1850'), 'before 1850');
    expect(meaning('bapt. 1891'), 'baptized 1891');
    expect(meaning('spring 1925'), 'about April 1925');
    expect(meaning('the 1880s'), 'between 1880 and 1889');
    expect(meaning('between 1880 and 1885'), 'between 1880 and 1885');
    expect(meaning('BET 1880 AND 1885'), 'between 1880 and 1885');
  });

  test('periods', () {
    expect(meaning('1946 to 1987'), '1946 to 1987');
    expect(meaning('1946-1987'), '1946 to 1987');
    expect(
      meaning('7 August 1941 to 27 September 1946'),
      '7 August 1941 to 27 September 1946',
    );
    expect(meaning('February to July 1934'), 'February 1934 to July 1934');
  });

  test('ambiguous numeric dates say so', () {
    final d = TreeDate.parse('3/4/1887');
    expect(d.ambiguous, isTrue);
    expect(d.meaning, contains('other way round'));
    expect(TreeDate.parse('3/14/1887').ambiguous, isFalse);
  });

  test('text that is not a date is not understood', () {
    for (final text in ['Brooklyn, NY', 'unknown', '', 'Founder & President']) {
      expect(TreeDate.parse(text).understood, isFalse, reason: text);
    }
  });

  test('dates sort by their earliest point', () {
    final dates =
        [
            '17 May 1950',
            '1946 to 1987',
            '6 January 1911',
            'about 1930',
            'November 1987',
          ].map(TreeDate.parse).toList()
          ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    expect(dates.map((d) => d.raw), [
      '6 January 1911',
      'about 1930',
      '1946 to 1987',
      '17 May 1950',
      'November 1987',
    ]);
  });
}
