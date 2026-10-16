import 'package:prosapia/src/page_format.dart';
import 'package:test/test.dart';

void main() {
  test('fact lines get single spaces', () {
    expect(
      formatPage('\n\nName:  Allan   Davidson \nNickname:  Scotty\nNote:\n'),
      'Name: Allan Davidson\nNickname: Scotty\nNote:\n',
    );
  });

  test('blank lines are collapsed and trailing space removed', () {
    expect(
      formatPage('Name: A\n\n\n\nOne.   \n\n\n\n## Two  \n\n\nThree.\n\n\n'),
      'Name: A\n\nOne.\n\n## Two\n\nThree.\n',
    );
  });

  test('paragraphs are joined and wrapped at 80 columns', () {
    final words = List.filled(30, 'word').join(' ');
    final out = formatPage('Name: A\n\nShort\nlines $words');
    expect(out.split('\n').skip(2).every((l) => l.length <= 80), isTrue);
    expect(out, startsWith('Name: A\n\nShort lines word word'));
  });

  test('links, marks and code are not split', () {
    final out = formatPage(
      'Name: A\n\n${'x' * 60} [place: Trinity Episcopal Church, Hartford] '
      'and [the  letter](https://example.com/a b) and `some code`.',
      width: 70,
    );
    expect(
      out,
      'Name: A\n\n${'x' * 60}\n'
      '[place: Trinity Episcopal Church, Hartford] and\n'
      '[the letter](https://example.com/a b) and `some code`.\n',
    );
  });

  test('a wrapped line never starts as a list or heading', () {
    final out = formatPage('Name: A\n\n${'x' * 75} - y\n${'x' * 77} # z 1. w');
    for (final line in out.split('\n').skip(2)) {
      expect(line, isNot(matches(RegExp(r'^([-#]|\d+\.) '))));
    }
  });

  test('list items wrap with a hanging indent', () {
    final long = List.filled(20, 'word').join(' ');
    expect(
      formatPage('Name: A\n\n-   one\n- $long\n  more\n1. x'),
      'Name: A\n\n- one\n- ${List.filled(15, 'word').join(' ')}\n'
      '  word word word word word more\n1. x\n',
    );
  });

  test('code, quotes and tables are kept as written', () {
    const page =
        'Name: A\n\n```\n  code   here  \n\n\n```\n\n> quoted   line\n> more\n\n'
        '| a  | b |\n|---|---|\n';
    expect(
      formatPage(page),
      page.replaceFirst('  code   here  ', '  code   here'),
    );
  });

  test('hard line breaks are kept', () {
    expect(
      formatPage('Name: A\n\nRoses are red,  \nviolets blue.\\\nThe end.'),
      'Name: A\n\nRoses are red,  \nviolets blue.\\\nThe end.\n',
    );
  });

  test('a page without facts is formatted as prose', () {
    expect(formatPage('Some  notes\nhere.'), 'Some notes here.\n');
  });

  test('formatting is stable', () {
    const page =
        'Name:  A\nBorn: 1900\n\nIntro  text\nmore.\n\n## 1920: A trip\n\n'
        '* a\n* b\n\n  c\n\nTitle\n=====\n\n---\n\n<div>x</div>\n';
    final once = formatPage(page);
    expect(formatPage(once), once);
  });
}
