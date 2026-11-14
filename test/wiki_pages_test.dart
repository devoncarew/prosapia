import 'package:prosapia/src/index.dart';
import 'package:prosapia/src/page_edits.dart';
import 'package:prosapia/src/page_format.dart';
import 'package:prosapia/src/render.dart';
import 'package:prosapia/src/server.dart' show itemIdTaken;
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  final tree = Tree('test');
  tree.media['m-gdcade'] = Media(
    'm-gdcade',
    isBack: false,
    extension: 'pdf',
    location: '',
  )..title = 'The Carews of Antony';
  final family = WikiPage.fromSource(
    'w-k3m9qa',
    'carew-family-k3m9qa',
    'Title: The Carew family\n\n'
        'The family came from Antony, in Cornwall; see #carews-antony-gdcade. '
        'Its first in America was @carew-john-a1a1a1.\n',
  );
  final house = WikiPage.fromSource(
    'w-h0use2',
    'house-h0use2',
    'Title: The house on Elm Street\n\nBuilt by @carew-john-a1a1a1.\n',
  );
  final john = Person.fromSource(
    'p-a1a1a1',
    'carew-john-a1a1a1',
    'Name: John Carew\nFamily: #carew-family-k3m9qa\n',
  );
  final mary = Person.fromSource(
    'p-b2b2b2',
    'carew-mary-b2b2b2',
    'Name: Mary Carew\nFamily: #carew-family-k3m9qa, #nothing-zzzzzz\n\n'
        'She wrote about #carew-family-k3m9qa.\n',
  );
  tree.pages[family.id] = family;
  tree.pages[house.id] = house;
  tree.people[john.id] = john;
  tree.people[mary.id] = mary;
  final r = Renderer(tree, Index.build(tree));

  test('a page reads its title and story', () {
    expect(family.title, 'The Carew family');
    expect(family.issues, isEmpty);
    expect(family.body, startsWith('The family came'));
    expect(family.reference, '#carew-family-k3m9qa');
    expect(family.mentioned, ['p-a1a1a1']);
  });

  test('a page without a Title line says so', () {
    final page = WikiPage.fromSource('w-aaaaaa', 'x-aaaaaa', 'Just text.\n');
    expect(page.issues, contains(contains('"Title:"')));
    expect(page.body, 'Just text.');
  });

  test('a Family line names pages by # reference', () {
    expect(john.families, ['w-k3m9qa']);
    expect(john.facts, isEmpty);
    expect(mary.families, ['w-k3m9qa', 'w-zzzzzz']);
    expect(
      r.issuesOf(mary),
      contains(contains('No page in the tree has the id w-zzzzzz')),
    );
  });

  test('a page is about the people who name it, then those it mentions', () {
    expect(r.peopleOf(family).map((p) => p.name), ['John Carew', 'Mary Carew']);
    expect(r.peopleOf(house).map((p) => p.name), ['John Carew']);
  });

  test("a person's page shows their families and the pages naming them", () {
    final pages = r.pagesFor(john);
    expect(pages.families, [family]);
    expect(pages.mentions, [house]);
    final html = r.personArticle(john);
    expect(html, contains('<th>Family</th>'));
    expect(html, contains('<a href="/pages/carew-family-k3m9qa">'));
    expect(html, contains('<th>Mentioned in</th>'));
  });

  test('a # reference in a story links to the page', () {
    expect(
      r.markdown(mary.body),
      contains('<a href="/pages/carew-family-k3m9qa">The Carew family</a>'),
    );
  });

  test('a page lists its people and the items its story names', () {
    final html = r.wikiArticle(family);
    expect(html, contains('<h2>People'));
    expect(html, contains('/people/carew-mary-b2b2b2'));
    expect(html, contains('Photos, documents and sources'));
    expect(html, contains('/media/m-gdcade'));
  });

  test('pages are found by search', () {
    final results = Index.build(tree).search('Antony');
    expect(results.map((x) => (x.kind, x.id)), contains(('page', 'w-k3m9qa')));
  });

  test('the People list links a family to its page', () {
    expect(r.people(), contains('<a href="/pages/carew-family-k3m9qa">'));
  });

  test('a page formats stably, keeping its title line', () {
    const typed = 'Title:   The  Carew family\n\nA story.\n';
    final once = formatPage(typed);
    expect(once, 'Title: The Carew family\n\nA story.\n');
    expect(formatPage(once), once);
  });

  test("a new page's directory is a few words of its title", () {
    expect(
      pageDirectoryFor('The Carew family', 'w-k3m9qa'),
      'carew-family-k3m9qa',
    );
    expect(pageDirectoryFor('…', 'w-k3m9qa'), 'page-k3m9qa');
  });

  test('ids are unique across items and pages', () {
    expect(itemIdTaken(tree, 'm-k3m9qa'), isTrue);
    expect(itemIdTaken(tree, 'w-gdcade'), isTrue);
    expect(itemIdTaken(tree, 'w-unused'), isFalse);
  });

  test('a Family line with several pages keeps them apart', () {
    final once = formatPage(
      'Name: John Carew\nFamily: #carew-family-k3m9qa, #house-h0use2\n',
    );
    expect(once, contains('Family: #carew-family-k3m9qa, #house-h0use2\n'));
  });
}
