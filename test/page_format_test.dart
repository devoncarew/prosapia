import 'package:prosapia/src/page_format.dart';
import 'package:prosapia/src/tree.dart';
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

  test('paragraphs are joined and wrapped at 88 columns', () {
    final words = List.filled(30, 'word').join(' ');
    final out = formatPage('Name: A\n\nShort\nlines $words');
    final lines = out.split('\n').skip(2).where((l) => l.isNotEmpty);
    expect(lines.every((l) => l.length <= 88), isTrue);
    expect(lines.first.length, greaterThan(80));
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
      formatPage('Name: A\n\n-   one\n- $long\n  more\n1. x', width: 80),
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

  group('fact lines', () {
    String facts(String lines) => formatPage('Name: A\n$lines\n');

    test('a value with commas is quoted', () {
      expect(
        facts('Born: 6 January 1911,  Brooklyn, NY, USA'),
        'Name: A\nBorn: 6 January 1911, "Brooklyn, NY, USA"\n',
      );
      expect(
        facts('Born: January 6, 1911, Brooklyn'),
        'Name: A\nBorn: "January 6, 1911", Brooklyn\n',
      );
    });

    test('quoted parts stay apart, and a doubtful date is a date', () {
      expect(
        facts('Born: "New York, NY", 1861 ?'),
        'Name: A\nBorn: "New York, NY", 1861 ?\n',
      );
      expect(
        facts('Born: 1861 ?, "New York, NY"'),
        'Name: A\nBorn: 1861 ?, "New York, NY"\n',
      );
      expect(
        facts('Buried: River View Cemetery, "Portland, Oregon"'),
        'Name: A\nBuried: River View Cemetery, "Portland, Oregon"\n',
      );
      // Without quotes, the forgiving reading still joins the place.
      expect(
        facts('Born: 1911, Brooklyn, NY'),
        'Name: A\nBorn: 1911, "Brooklyn, NY"\n',
      );
    });

    test('something meant as a date is never part of the place', () {
      expect(
        facts('Born: "New York, NY", 1861 or 1862'),
        'Name: A\nBorn: "New York, NY", 1861 or 1862\n',
      );
    });

    test('a date after the place stays the date', () {
      expect(
        facts('Born: "Portland, Oregon", "18 March 1914"'),
        'Name: A\nBorn: "Portland, Oregon", 18 March 1914\n',
      );
      expect(
        facts('Died: Portland, Oregon, 1987'),
        'Name: A\nDied: "Portland, Oregon", 1987\n',
      );
    });

    test('a place beside a named partner is labelled', () {
      expect(
        facts('Married: Ann Price, 1884, Hartford, CT'),
        'Name: A\nMarried: Ann Price, 1884, place: "Hartford, CT"\n',
      );
    });

    test('marks become labels', () {
      expect(
        facts('Occupation: teacher, 1908 to 1920, [place: Scranton, PA]'),
        'Name: A\nOccupation: teacher, 1908 to 1920, place: "Scranton, PA"\n',
      );
    });

    test('a long line is carried on, and reads the same', () {
      const line =
          'Married: @howard-irene-genevive-4dd34j, 4 August 1910, '
          'Brooklyn, New York City, New York, '
          'source: "New York, New York City Marriage Records, 1829-1938"';
      final out = facts(line);
      expect(
        out,
        'Name: A\n'
        'Married: @howard-irene-genevive-4dd34j, 4 August 1910,\n'
        '  "Brooklyn, New York City, New York",\n'
        '  source: "New York, New York City Marriage Records, 1829-1938"\n',
      );
      expect(formatPage(out), out);
    });

    test('a part too long for a line is broken between words', () {
      const line =
          'Occupation: hand on S.C. Loveland motor ship & cadet on S.S. Zarembo '
          'of Barber Steamship Co. between US and Africa, February to July 1934';
      final out = formatPage('Name: A\n$line\n', width: 80);
      expect(
        out,
        'Name: A\n'
        'Occupation: hand on S.C. Loveland motor ship & cadet on S.S. Zarembo of Barber\n'
        '  Steamship Co. between US and Africa,\n'
        '  February to July 1934\n',
      );
      expect(out.split('\n').every((l) => l.length <= 80), isTrue);
      expect(formatPage(out, width: 80), out);
    });

    test('a long note is broken between words, and reads the same', () {
      const note =
          'Note: In 2026 the Canadian writer Matthew Walthert published a book about '
          'Scotty. Peter Carew helped by answering questions about family records '
          'and providing several of the photographs in it.';
      final out = facts(note);
      expect(
        out,
        'Name: A\n'
        'Note: In 2026 the Canadian writer Matthew Walthert published a book about Scotty. Peter\n'
        '  Carew helped by answering questions about family records and providing several of the\n'
        '  photographs in it.\n',
      );
      expect(formatPage(out), out);
      final read = Person.fromSource('p-0', 'x-0', out).notes.single;
      expect('Note: $read', note);
    });

    test('a line that would read differently is kept as written', () {
      // "Jr." would become a second child if the parts were quoted apart.
      expect(
        facts('Children: Margaret Hughes, Jr.'),
        'Name: A\nChildren: Margaret Hughes, Jr.\n',
      );
      expect(facts('Note: one,  two'), 'Name: A\nNote: one, two\n');
    });
  });
}
