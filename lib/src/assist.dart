import 'dart:io';

import 'claude.dart';
import 'diff.dart';
import 'index.dart';
import 'page_syntax.dart';
import 'tree.dart';

/// What can be asked of the model from the editor.
enum HelpRequest {
  /// Write the story of a page that has none.
  draft,

  /// Rewrite the whole story.
  revise,

  /// Rewrite only the selected text.
  selection;

  static HelpRequest? byName(String? name) =>
      values.where((r) => r.name == name).firstOrNull;
}

/// Help from a language model with writing a page, following the rules in
/// docs/design.md and the voice in docs/writing.md. Nothing here saves
/// anything: it returns text for a person to keep or undo.
class Assistant {
  Assistant(this.claude, this.guide);

  final Claude claude;
  final WritingGuide guide;

  /// Rewrites part of [person]'s page. [source] is the page as it stands in
  /// the editor, not yet saved; for [HelpRequest.selection], [from] and [to]
  /// are the selected range in it. [guidance] is an optional sentence from
  /// the editor. Returns the new story, or the selection's replacement.
  Future<Reply> help(
    HelpRequest request, {
    required Person person,
    required String source,
    required Tree tree,
    required Index index,
    int from = 0,
    int to = 0,
    String guidance = '',
  }) {
    final page = ParsedPage.parse(source);
    // A selection is improved on its own terms; the relatives and photos
    // would only invite the model to add to it.
    final context = request == HelpRequest.selection
        ? ''
        : _context(person, source, tree, index);
    final task = switch (request) {
      HelpRequest.draft =>
        'The story below the facts is empty. Write it: the markdown that '
            'follows the facts block, from what the page, the people and the '
            'photos say.',
      HelpRequest.revise =>
        'Rewrite the story below the facts so it reads well and follows the '
            'guide. Keep everything it says, and its dated `##` sections. '
            'Bring in facts from the facts block that the story leaves out, '
            'where they fit.',
      HelpRequest.selection =>
        'Improve only the text between <selected> and </selected>. Work out '
            'what is wanted from the selection itself: notes or a list of '
            'facts become a clear paragraph; rough or dictated prose is '
            'tidied, with its grammar and voice improved; prose that already '
            'reads well needs only light changes. Use only what the selection '
            'says: do not bring in facts from the rest of the page, and do not '
            'try to fill out the biography. The rest of the page is there '
            'only so the new text fits the voice and flow around it.',
    };
    final marked = request == HelpRequest.selection
        ? '${source.substring(0, from)}<selected>${source.substring(from, to)}'
              '</selected>${source.substring(to)}'
        : source;
    final user = StringBuffer()
      ..writeln('<page>')
      ..writeln(marked.trimRight())
      ..writeln('</page>')
      ..writeln()
      ..write(context)
      ..writeln()
      ..writeln(task);
    if (guidance.trim().isNotEmpty) {
      user
        ..writeln()
        ..writeln('The editor adds: ${guidance.trim()}');
    }
    user
      ..writeln()
      ..writeln(
        request == HelpRequest.selection
            ? 'Reply with only the replacement text, in markdown.'
            : 'Reply with only the story, in markdown, without the facts '
                  'block.',
      );
    if (page.body.isEmpty && request == HelpRequest.revise) {
      // Nothing to revise; draft instead.
      return help(
        HelpRequest.draft,
        person: person,
        source: source,
        tree: tree,
        index: index,
        guidance: guidance,
      );
    }
    return _clean(
      claude.write(
        Model.writer,
        system: _system(guide.biographies),
        user: user.toString(),
      ),
    );
  }

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
