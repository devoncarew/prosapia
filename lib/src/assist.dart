import 'dart:io';

import 'claude.dart';
import 'diff.dart';
import 'gather.dart';
import 'index.dart';
import 'page_syntax.dart';
import 'tree.dart';

/// Help from a language model with writing a page, following the rules in
/// docs/design.md and the voice in docs/writing.md. Nothing here saves
/// anything: it returns text for a person to keep or undo.
class Assistant {
  Assistant(this.claude, this.guide);

  final Claude claude;
  final WritingGuide guide;

  /// What "Claude: Draft…" suggests doing when a page has no story yet.
  static const firstDraft =
      'Write a short biography from the facts, memories and photo captions.';

  /// Writes the story of [person]'s page. [source] is the page as it stands
  /// in the editor, not yet saved. [instruction] says what is wanted, and
  /// [notes] is new information to work in: notes, a letter, an obituary.
  /// An empty story is drafted from the page and the people around it; an
  /// existing one keeps its wording wherever it can. Returns the new story.
  Future<Reply> draft({
    required Person person,
    required String source,
    required Tree tree,
    required Index index,
    String instruction = '',
    String notes = '',
  }) {
    final page = ParsedPage.parse(source);
    final fresh = page.body.isEmpty;
    final task = fresh
        ? 'The story below the facts is empty. Write it: the markdown that '
              'follows the facts block, from what the page, the people and the '
              'photos say. From what the tree says elsewhere, choose the few '
              'details that tell most about this life, and leave out the rest: '
              'the facts box already lists every fact. Use an excerpt found by '
              'name only when it is clearly about this person.'
        : 'Rewrite the story below the facts as the editor asks. Keep its '
              'wording, its order and its dated `##` sections wherever you '
              'can, and change only what the request and the notes need: a '
              'sentence that is already right stays exactly as it is.';
    final user = StringBuffer()
      ..writeln('<page>')
      ..writeln(source.trimRight())
      ..writeln('</page>')
      ..writeln()
      ..write(_context(person, source, tree, index))
      ..writeln();
    // A first draft draws on the whole tree; a revision works in what the
    // editor gives it, and extra material would only invite additions.
    if (fresh) user.write(_elsewhere(person, tree, index));
    if (notes.trim().isNotEmpty) {
      user
        ..writeln(
          '<notes>\nNew information from the editor, to work into the story. '
          'Use what it says; do not add to it.\n\n${notes.trim()}\n</notes>',
        )
        ..writeln();
    }
    user
      ..writeln(task)
      ..writeln()
      ..writeln(
        'The editor asks: ${instruction.trim().isEmpty ? (page.body.isEmpty ? firstDraft : 'Improve the story so it reads well and follows the guide.') : instruction.trim()}',
      )
      ..writeln()
      ..writeln(
        'Reply with only the story, in markdown, without the facts block.'
        '${fresh ? ' If the story uses anything from <elsewhere>, end with a '
                  'line `$drawnFromMarker` and then a list with one line for '
                  'each source used: where it was found, and what it gave, such '
                  'as "- Michael Carew\'s page: the year she moved to Hartford".' : ''}',
      );
    return _clean(
      claude.write(
        Model.writer,
        system: _system(guide.biographies),
        user: user.toString(),
      ),
    );
  }

  /// Where to look next for [person]: specific records that would fill the
  /// gaps on their page, and where to find them. Advice only, in markdown.
  Future<Reply> researchIdeas({
    required Person person,
    required Tree tree,
    required Index index,
  }) => _clean(
    claude.write(
      Model.writer,
      system:
          'You help members of a family-history wiki find records about '
          'their relatives. They are capable but new to genealogy research. '
          'Suggest specific records, not general advice: which record, for '
          'which place and years, and on which site. Prefer the free sites '
          'listed below, and say when a record is only on a paid one.\n\n'
          '$_researchSites',
      user:
          '<page>\n${person.source.trimRight()}\n</page>\n\n'
          '${_context(person, person.source, tree, index)}\n'
          '${_elsewhere(person, tree, index)}'
          'Do not suggest looking for what the page or the tree already '
          'says, unless a record would confirm it.\n\n'
          'Suggest four to six records to look for about ${person.name}, the '
          'most useful first. For each, in one or two sentences: what to '
          'search for and where, and which gap on the page it would fill or '
          'which fact it would confirm. Do not state any fact about '
          '${person.name} that the page does not; you are suggesting where '
          'to look, not what will be found. If the page names a living '
          'person, do not suggest searching for them.\n\n'
          'Reply with only a markdown list.',
    ),
  );

  static const _researchSites = '''
Free: FamilySearch (censuses, births, marriages, deaths, church and immigration records; its Research Wiki says which records exist for a place and time); US censuses 1790 to 1950, on FamilySearch; Find a Grave and BillionGraves (cemeteries and headstones); Chronicling America (historic US newspapers); the US National Archives (immigration, naturalization, military service); Ellis Island passenger lists (New York arrivals); Library and Archives Canada; FreeBMD (England and Wales births, marriages and deaths from 1837); the Internet Archive and Google Books (county histories, city directories, yearbooks, family histories); public libraries, which often offer Ancestry Library Edition and newspaper archives free.
Paid: Ancestry; Newspapers.com and GenealogyBank (obituaries, notices, local news); Fold3 (US military records); MyHeritage and Findmypast (Europe, Britain and Ireland).''';

  /// Tidies a memory as typed or dictated, keeping the teller's voice.
  Future<Reply> tidyMemory(Person person, String title, String text) => _clean(
    claude.write(
      Model.fast,
      effort: 'low',
      system: _system(
        'Tidy a memory someone has typed or dictated about a relative. Fix '
        'spelling, punctuation and obvious dictation errors, and break it '
        'into paragraphs. Keep their words, their voice and their order. Do '
        'not add anything, and do not remove anything they said.',
      ),
      user:
          'A memory of ${person.name}${title.isEmpty ? '' : ', titled "$title"'}:\n\n'
          '<memory>\n${text.trim()}\n</memory>\n\n'
          'Reply with only the tidied memory.',
    ),
  );

  /// Transcribes the writing on the back of a photo, given as a JPEG.
  Future<Reply> transcribeBack(List<int> jpeg) => _clean(
    claude.write(
      Model.writer,
      images: [jpeg],
      system:
          'You transcribe the writing on the backs of old family photos, for '
          'a family-history wiki.',
      user:
          'This is the back of a photo. Transcribe the writing on it exactly '
          'as written, keeping its line breaks, spelling and abbreviations. '
          'Write [illegible] for a word you cannot read, and [?] after a '
          'word you are unsure of. Ignore printed processing marks unless '
          'they include a date. If there is no writing, reply with nothing. '
          'Reply with only the transcription.',
    ),
  );

  /// A one-line summary of a change from each page's text before and after.
  Future<Reply> summarize(
    List<({String name, String before, String after})> pages,
  ) {
    final user = StringBuffer();
    for (final page in pages) {
      user.writeln('<page name="${page.name}">');
      for (final line in diffLines(page.before, page.after)) {
        if (line.kind == DiffKind.same) continue;
        user.writeln('${line.kind == DiffKind.added ? '+' : '-'} ${line.text}');
      }
      user.writeln('</page>');
    }
    user.writeln(
      '\nThese are the lines added (+) and removed (-) in one change. '
      'Reply with only its one-line summary.',
    );
    return _clean(
      claude.write(
        Model.fast,
        effort: 'low',
        maxTokens: 4000,
        system: _system(guide.summaries),
        user: user.toString(),
      ),
    );
  }

  static String _system(String guide) =>
      'You help a family keep its history in Prosapia, a family-history '
      'wiki. Each person has a page: a block of "Label: value" facts, then a '
      'story in markdown. People are linked with @ references such as '
      '@hughes-thomas-3f8d1a; use only references given to you.\n\n'
      'Follow this guide:\n\n$guide';

  /// Who and what the page refers to, so the model can name people and
  /// link them.
  static String _context(Person person, String source, Tree tree, Index index) {
    final people = <String, String>{};
    void add(String id, String relation) {
      final p = tree.people[id];
      if (p == null || people.containsKey(p.reference)) return;
      people[p.reference] =
          '${p.name}${p.years.isEmpty ? '' : ' (${p.years})'}'
          '${relation.isEmpty ? '' : ', ${person.name}\'s $relation'}';
    }

    for (final id in index.parentsOf(person.id)) {
      add(id, 'parent');
    }
    for (final id in index.partnersOf(person.id)) {
      add(id, 'partner');
    }
    for (final id in index.childrenOf(person.id)) {
      add(id, 'child');
    }
    for (final id in index.siblingsOf(person.id)) {
      add(id, 'sibling');
    }
    for (final m in proseRef.allMatches(source)) {
      add('p-${m[1]!.split('-').last}', '');
    }
    final photos = [
      for (final key in index.mediaOf(person.id))
        if (tree.media[key] case final m? when m.title != null)
          '- ${m.title}${m.description == null ? '' : ': ${m.description}'}',
    ];
    final sb = StringBuffer('<people>\n');
    people.forEach((ref, about) => sb.writeln('$ref: $about'));
    sb.writeln('</people>');
    if (photos.isNotEmpty) {
      sb
        ..writeln('<photos>')
        ..writeln(photos.join('\n'))
        ..writeln('</photos>');
    }
    return sb.toString();
  }

  /// What the tree says about [person] away from their page, for the
  /// model, or nothing if it says nothing.
  static String _elsewhere(Person person, Tree tree, Index index) {
    final excerpts = elsewhere(person, tree, index);
    if (excerpts.isEmpty) return '';
    final sb = StringBuffer(
      '<elsewhere>\nWhat the tree says about ${person.name} away from their '
      'own page.\n\n',
    );
    for (final e in excerpts) {
      sb
        ..writeln(
          '<excerpt from="${e.from}"${e.byName ? ' found="by name only; may be someone else"' : ''}>',
        )
        ..writeln(e.text)
        ..writeln('</excerpt>');
    }
    sb.writeln('</elsewhere>');
    return sb.toString();
  }

  /// The line a first draft ends its story with, before saying where facts
  /// from elsewhere in the tree came from.
  static const drawnFromMarker = '---drawn-from---';

  /// A first draft's story, and the list of where it drew facts from
  /// elsewhere in the tree.
  static ({String story, List<String> drawnFrom}) splitDrawnFrom(String text) {
    final at = text.indexOf(drawnFromMarker);
    if (at < 0) return (story: text.trim(), drawnFrom: const []);
    return (
      story: text.substring(0, at).trim(),
      drawnFrom: [
        for (final line
            in text.substring(at + drawnFromMarker.length).split('\n'))
          if (line.trim().replaceFirst(RegExp(r'^[-*]\s*'), '') case final item
              when item.isNotEmpty)
            item,
      ],
    );
  }

  /// Removes a code fence the model may wrap its reply in.
  static Future<Reply> _clean(Future<Reply> reply) async {
    final r = await reply;
    final m = RegExp(
      r'^```(?:markdown|md)?\n(.*)\n```$',
      dotAll: true,
    ).firstMatch(r.text);
    return m == null
        ? r
        : Reply(m[1]!.trim(), r.model, cost: r.cost, refused: r.refused);
  }
}

/// The voice for biographies and the pattern for change summaries, read
/// from docs/writing.md so the guide people read is the one the model
/// follows.
class WritingGuide {
  WritingGuide({required this.biographies, required this.summaries});

  factory WritingGuide.load([String path = 'docs/writing.md']) {
    final sections = <String, String>{};
    String? heading;
    final body = StringBuffer();
    void close() {
      if (heading case final h?) sections[h] = body.toString().trim();
      body.clear();
    }

    for (final line in File(path).readAsLinesSync()) {
      if (line.startsWith('## ')) {
        close();
        heading = line.substring(3).trim().toLowerCase();
      } else {
        body.writeln(line);
      }
    }
    close();
    return WritingGuide(
      biographies: sections['biographies'] ?? '',
      summaries: sections['change summaries'] ?? '',
    );
  }

  final String biographies;
  final String summaries;
}
