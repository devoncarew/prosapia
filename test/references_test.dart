import 'package:prosapia/src/index.dart';
import 'package:prosapia/src/page_edits.dart';
import 'package:prosapia/src/render.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  final tree = Tree('test');
  tree.media['m-gdcade'] = Media(
    'm-gdcade',
    isBack: false,
    extension: 'jpg',
    location: '',
  )..title = 'Marriage certificate';
  final page = Person.fromSource(
    'p-a1a1a1',
    'a-a1a1a1',
    'Name: A\nPhoto: #m-gdcade\nFamilySearch: LZ5X-QRT\n'
        'Married: B, 1910, source: "#m-gdcade, page 2"\n'
        'Born: 1890, source: #m-nothin\n\n'
        'They married in 1910 [source: #m-gdcade] and moved [source: 1920 census]. '
        'See #m-gdcade, and the letter [source: 1920 census]. Not a link: '
        '[top](#top), # Heading.\n',
  );
  tree.people[page.id] = page;
  final r = Renderer(tree, Index.build(tree));

  test('a # reference in the story links to the item', () {
    final html = r.markdown(page.body);
    expect(
      html,
      contains('<a href="/media/m-gdcade">Marriage certificate</a>'),
    );
    expect(html, contains('href="#top"'));
  });

  test('story sources are numbered, and listed after it', () {
    final html = r.markdown(page.body);
    expect(RegExp('class="cite-ref"').allMatches(html), hasLength(3));
    expect(
      html,
      contains(
        '<li id="source-1"><a href="/media/m-gdcade">Marriage certificate</a></li>',
      ),
    );
    expect(html, contains('<li id="source-2">1920 census</li>'));
    expect(html, isNot(contains('source-3')));
  });

  test('a fact cites a document, with detail', () {
    expect(
      r.cite(page.couples.single.event),
      contains('href="/media/m-gdcade" title="Marriage certificate, page 2"'),
    );
  });

  test('the photo, other ids, and what matches nothing', () {
    expect(page.photo, 'm-gdcade');
    expect(page.externalIds, {'FamilySearch': 'LZ5X-QRT'});
    expect(page.facts, isEmpty);
    expect(r.issuesOf(page), ['Nothing in the tree matches #m-nothin.']);
  });

  test('an item lists what cites it', () {
    final html = r.media(tree.media['m-gdcade']!);
    expect(html, contains('<h2>Cited by</h2>'));
    expect(
      html,
      contains('Married, cited in the story, mentioned in the story'),
    );
  });

  test("a page's sources are gathered in one place", () {
    final html = r.personArticle(page);
    expect(html, contains('<section class="sources"><h2>Sources</h2><ol>'));
    expect(html, contains('<span class="kind">Married</span>'));
    expect(RegExp('<h2>Sources</h2>').allMatches(html), hasLength(1));
  });

  test('a birth or death known only by its place is in Also recorded', () {
    final t = Tree('test');
    final p = Person.fromSource(
      'p-b2b2b2',
      'b-b2b2b2',
      'Name: B\nBorn: Ontario, Canada\nDied:\n',
    );
    t.people[p.id] = p;
    final html = Renderer(t, Index.build(t)).personArticle(p);
    expect(html, contains('<h2>Also recorded</h2>'));
    expect(
      html,
      contains('<li>Born <span class="place">Ontario, Canada</span>'),
    );
    expect(html, isNot(contains('<li>Died')));
  });

  test('a note cites its source and links its references', () {
    final p = Person.fromSource(
      'p-c3c3c3',
      'c-c3c3c3',
      'Name: C\nNote: Father of @a-a1a1a1, born in Ireland, '
          'source: #marriage-certificate-gdcade\n',
    );
    tree.people[p.id] = p;
    final html = r.personArticle(p);
    expect(
      html,
      contains(
        'Father of <a href="/people/a-a1a1a1">A</a>, born in Ireland '
        '<a class="cite" href="/media/m-gdcade"',
      ),
    );
    expect(html, isNot(contains('source: #')));
    expect(r.citationsOn(p).single, (
      where: 'Note',
      source: '#marriage-certificate-gdcade',
    ));
    tree.people.remove(p.id);
  });

  test('readable item references', () {
    expect(
      itemReference('Obituary of Thomas Hughes, Scranton Times', 'm-gdcade'),
      '#obituary-thomas-hughes-scranton-gdcade',
    );
    expect(itemReference(null, 'm-gdcade'), '#m-gdcade');
    expect(
      itemOf(tree, '#obituary-thomas-hughes-scranton-gdcade')?.key,
      'm-gdcade',
    );
    expect(
      Person.fromSource(
        'p-d4d4d4',
        'd-d4d4d4',
        'Name: D\nPhoto: #wedding-gdcade\n',
      ).photo,
      'm-gdcade',
    );
  });
}
