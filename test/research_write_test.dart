import 'dart:io';

import 'package:prosapia/src/research.dart';
import 'package:prosapia/src/research_write.dart';
import 'package:prosapia/src/store.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

/// A store in memory that records what is saved, and refuses a save based
/// on an old revision, as the real stores do.
class MemoryStore extends TreeStore {
  MemoryStore(this.tree);

  final Tree tree;
  final saved =
      <
        ({
          List<PageWrite> pages,
          String summary,
          String? helpedBy,
          String? summaryBy,
        })
      >[];
  final media =
      <({List<MediaWrite> files, String summary, String? helpedBy})>[];

  @override
  Future<Tree> load() async => tree;
  @override
  Future<int> version() async => 0;
  @override
  Future<File> localFile(Media media) async => File(media.location);
  @override
  Future<Member?> member(String email) async => Member(email, Role.editor);
  @override
  bool get requiresSignIn => false;
  @override
  bool get editable => true;

  @override
  Future<SaveResult> saveChange(
    List<PageWrite> pages, {
    required Member author,
    required String summary,
    String? helpedBy,
    String? summaryBy,
  }) async {
    final current =
        tree.people[pages.first.page.id] ?? tree.pages[pages.first.page.id];
    if (current != null && current.revision != pages.first.basedOn) {
      return SaveResult.conflict(current.revision);
    }
    saved.add((
      pages: pages,
      summary: summary,
      helpedBy: helpedBy,
      summaryBy: summaryBy,
    ));
    return SaveResult.saved(pages.first.basedOn + 1);
  }

  @override
  Future<void> saveMedia(
    List<MediaWrite> files, {
    required Member author,
    required String summary,
    String? helpedBy,
  }) async => media.add((files: files, summary: summary, helpedBy: helpedBy));
}

Tree _tree() {
  final tree = Tree('test');
  tree.people['p-k3m9qa'] = Person.fromSource(
    'p-k3m9qa',
    'carew-michael-k3m9qa',
    '''
Name: Michael Carew
Born: 1853
Died: 1927
Parents: @nobody-zzzzzz

He was a carpenter.
''',
    revision: 4,
  );
  tree.people['p-a1b2c3'] = Person.fromSource(
    'p-a1b2c3',
    'burns-ellen-a1b2c3',
    '''
Name: Ellen Burns
''',
  );
  tree.media['m-c4n5us'] = Media(
    'm-c4n5us',
    isBack: false,
    extension: '',
    location: '',
  )..title = '1860 census';
  return tree;
}

final _me = Member('owner@example.com', Role.owner);

void main() {
  late Tree tree;
  late Research research;
  late Person michael;
  setUp(() {
    tree = _tree();
    research = Research(tree);
    michael = tree.people['p-k3m9qa']!;
  });

  group('PageEdit', () {
    test('shows the change as a diff with context', () {
      final edit = PageEdit.replace(
        research,
        michael,
        michael.source.replaceFirst(
          'Died: 1927',
          'Died: 2 August 1927, source: #m-c4n5us',
        ),
      );
      expect(edit.changed, isTrue);
      expect(edit.issues, isEmpty);
      expect(edit.diff(context: 1), '''
 Born: 1853
-Died: 1927
+Died: 2 August 1927, source: #m-c4n5us
 Parents: @nobody-zzzzzz''');
    });

    test('the same text, or only reformatted, is no change', () {
      expect(
        PageEdit.replace(research, michael, michael.source).changed,
        isFalse,
      );
      expect(
        PageEdit.replace(research, michael, '${michael.source}\n\n').changed,
        isFalse,
      );
    });

    test(
      'lists only the problems the new text brings, such as a placeholder',
      () {
        final edit = PageEdit.replace(
          research,
          michael,
          michael.source.replaceFirst(
            'Died: 1927',
            'Died: 1927, source: #NEW-1927',
          ),
        );
        // The existing bad parent reference is not this edit's doing.
        expect(edit.issues, ['Nothing in the tree matches #NEW-1927.']);
      },
    );

    test('appends a section to the story', () {
      final edit = PageEdit.append(
        research,
        michael,
        '## 1927: Death\n\nHe died in the Bronx.\n',
      );
      expect(
        edit.after,
        endsWith(
          'He was a carpenter.\n\n## 1927: Death\n\nHe died in the Bronx.\n',
        ),
      );
      expect(edit.diff(), contains('+## 1927: Death'));
    });

    group('with a Notes section', () {
      final page = Person.fromSource(
        'p-k3m9qa',
        'carew-michael-k3m9qa',
        'Name: Michael Carew\n\nHe was a carpenter.\n\n## Notes\n\n'
            '- Not in the 1880 census.\n',
      );

      test('puts a story section before it', () {
        final edit = PageEdit.append(
          research,
          page,
          '## 1927: Death\n\nHe died in the Bronx.\n',
        );
        expect(
          edit.after,
          endsWith(
            'He was a carpenter.\n\n## 1927: Death\n\nHe died in the '
            'Bronx.\n\n## Notes\n\n- Not in the 1880 census.\n',
          ),
        );
      });

      test('adds notes to it', () {
        final edit = PageEdit.append(
          research,
          page,
          '## Notes\n\n- Not in the 1890 directory.\n',
        );
        expect(
          edit.after,
          endsWith(
            '## Notes\n\n- Not in the 1880 census.\n'
            '- Not in the 1890 directory.\n',
          ),
        );
      });
    });

    test(
      'saves with the summary and who helped, or refuses an old revision',
      () async {
        final store = MemoryStore(tree);
        final edit = PageEdit.replace(
          research,
          michael,
          michael.source.replaceFirst('1853', 'about 1853'),
        );
        final result = await edit.save(
          store,
          basedOn: 4,
          author: _me,
          summary: 'Add his birth',
          helpedBy: 'claude-opus-5-5',
        );
        expect(result.revision, 5);
        final change = store.saved.single;
        expect(change.pages.single.page.source, contains('Born: about 1853'));
        expect(change.pages.single.basedOn, 4);
        expect(change.helpedBy, 'claude-opus-5-5');
        expect(change.summaryBy, 'claude-opus-5-5');

        final stale = await edit.save(
          store,
          basedOn: 3,
          author: _me,
          summary: 'x',
        );
        expect(stale.saved, isFalse);
        expect(stale.conflictWith, 4);
      },
    );
  });

  group('NewItem', () {
    test('reads details, with people by any kind of reference', () {
      final item = NewItem.read(research, {
        'title': 'Death of Michael F. Carew',
        'date': '2 August 1927',
        'people': ['@carew-michael-k3m9qa', 'p-a1b2c3'],
        'link': 'https://example.com/record',
      });
      expect(item.details.people.map((p) => p.id), ['p-k3m9qa', 'p-a1b2c3']);
      expect(item.toJson()['people'], [
        'Michael Carew (p-k3m9qa)',
        'Ellen Burns (p-a1b2c3)',
      ]);
    });

    test('says what is wrong with the details', () {
      for (final (json, message) in [
        (<String, Object?>{'date': '1927'}, 'An item needs a title.'),
        ({'title': 'x', 'author': 'y'}, contains('"author" is not a detail')),
        (
          {
            'title': 'x',
            'people': ['nobody-zzzzzz'],
          },
          'No person in the tree matches nobody-zzzzzz.',
        ),
        ({'title': 'x', 'date': 1927}, '"date" should be text.'),
      ]) {
        expect(
          () => NewItem.read(research, json),
          throwsA(
            isA<FormatException>().having((e) => e.message, 'message', message),
          ),
        );
      }
    });

    test('refuses a file that is not a photo or document', () {
      final dir = Directory.systemTemp.createTempSync('item_test');
      final file = File('${dir.path}/notes.txt')..writeAsStringSync('hello');
      expect(
        () => NewItem.read(research, {'title': 'x'}, file: file),
        throwsA(isA<FormatException>()),
      );
      dir.deleteSync(recursive: true);
    });

    test('saves an item without a file, with a new id', () async {
      final store = MemoryStore(tree);
      final saved = await NewItem.read(research, {
        'title': '1920 census',
        'people': ['p-k3m9qa'],
        'link': 'https://example.com/ark',
        'found': '18 November 2026, FamilySearch',
      }).save(store, tree, author: _me, helpedBy: 'claude-opus-5-5');
      expect(saved.id, matches(RegExp(r'^m-[a-z0-9]{6}$')));
      expect(saved.id, isNot('m-c4n5us'));
      expect(saved.hasFile, isFalse);
      expect(saved.link, 'https://example.com/ark');
      expect(saved.found, '18 November 2026, FamilySearch');
      expect(saved.people, ['p-k3m9qa']);
      expect(store.media.single.summary, 'Add a source: 1920 census');
      expect(store.media.single.helpedBy, 'claude-opus-5-5');
    });

    test(
      'saves a PDF with its details written into it',
      () async {
        final store = MemoryStore(tree);
        final saved = await NewItem.read(
          research,
          {'title': 'Two pages', 'link': 'https://example.com/pdf'},
          file: File('test/fixtures/two_pages.pdf'),
        ).save(store, tree, author: _me, summary: 'Add a death certificate');
        expect(saved.extension, 'pdf');
        expect(saved.link, 'https://example.com/pdf');
        final write = store.media.single;
        expect(write.summary, 'Add a death certificate');
        expect(write.files.single.file!.existsSync(), isTrue);
      },
      skip: Process.runSync('which', ['exiftool']).exitCode == 0
          ? false
          : 'needs exiftool',
    );
  });

  group('ItemEdit', () {
    late Media census;
    setUp(() {
      census = tree.media['m-c4n5us']!
        ..notes = 'page 166'
        ..people.add('p-k3m9qa');
    });

    test('changes what is given, clears what is empty, keeps the rest', () {
      final edit = ItemEdit.read(research, census, {
        'link': 'https://www.familysearch.org/ark:/61903/1:1:MC7L-6T4',
        'notes': '',
      });
      expect(edit.changes.keys, ['notes', 'link']);
      expect(edit.changes['notes'], (from: 'page 166', to: null));
      expect(edit.details.title, '1860 census');
      expect(edit.details.people.single.id, 'p-k3m9qa');
      expect(
        ItemEdit.read(research, census, {'title': '1860 census'}).changed,
        isFalse,
      );
    });

    test('replaces the people as a whole, and needs a title', () {
      final edit = ItemEdit.read(research, census, {
        'people': ['@burns-ellen-a1b2c3'],
      });
      final people = edit.changes['people']!;
      expect(people.from, ['Michael Carew (p-k3m9qa)']);
      expect(people.to, ['Ellen Burns (p-a1b2c3)']);
      expect(
        () => ItemEdit.read(research, census, {'title': ''}),
        throwsFormatException,
      );
    });

    test('saves an item without a file, with who helped', () async {
      final store = MemoryStore(tree);
      await ItemEdit.read(research, census, {
        'link': 'https://example.com/ark',
      }).save(store, author: _me, helpedBy: 'claude-opus-5-5');
      final saved = store.media.single;
      expect(saved.summary, 'Change the details of 1860 census');
      expect(saved.helpedBy, 'claude-opus-5-5');
      final item = saved.files.single.media;
      expect(item.id, 'm-c4n5us');
      expect(item.link, 'https://example.com/ark');
      expect(item.notes, 'page 166');
      expect(item.people, ['p-k3m9qa']);
    });
  });

  test('unifiedDiff marks skipped lines', () {
    final before = [for (var i = 1; i <= 10; i++) 'line $i'].join('\n');
    final after = before
        .replaceFirst('line 2', 'line two')
        .replaceFirst('line 9', 'line nine');
    expect(unifiedDiff(before, after, context: 1), '''
 line 1
-line 2
+line two
 line 3
…
 line 8
-line 9
+line nine
 line 10''');
  });
}
