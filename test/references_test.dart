import 'package:prosapia/src/index.dart';
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
}
