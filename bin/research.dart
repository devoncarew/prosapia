import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:prosapia/src/claude.dart';
import 'package:prosapia/src/env.dart';
import 'package:prosapia/src/file_store.dart';
import 'package:prosapia/src/firestore_store.dart';
import 'package:prosapia/src/lookup.dart';
import 'package:prosapia/src/research.dart';
import 'package:prosapia/src/research_write.dart';
import 'package:prosapia/src/store.dart';
import 'package:prosapia/src/tree.dart';

const usage = '''
Read and write a tree for research, in Firestore or (reading only) a tree's files.

Reading, as JSON:
  dart run prosapia:research [options] show <id>     a page, its family and items
  dart run prosapia:research [options] gaps <id>     what a person's page lacks
  dart run prosapia:research [options] find <name>   people matching a name
      [--born <year>] [--within <years>] [--place <text>]

Writing: each shows what it would save, and saves only with --apply.
  dart run prosapia:research [options] edit <id> --file <page.md>
      --based-on <revision> --summary <text>       replace a page's text
  dart run prosapia:research [options] append <id> --file <section.md>
      --summary <text>                             add a section to the story
  dart run prosapia:research [options] add-item --details <json> [--file <file>]
                                                   add an item, with or without a file
Writes are saved as --by, a member who may edit, with --helped-by in the history.

Searching the free sources, as JSON; neither needs a tree:
  dart run prosapia:research lookup newspapers <words>  Chronicling America pages
      [--years 1890-1900] [--place <US state>]
  dart run prosapia:research lookup books <query>       Internet Archive texts
      [--years 1880-1920]
  dart run prosapia:research lookup wikitree <name>     WikiTree profiles, as leads
      [--born <year>]
  dart run prosapia:research text <link> <words>        the passages with <words>
      [--context <lines>]                              in a page or text found
A newspaper or book's "item" is details that add-item takes as they are.

<id> is a page's id or reference: carew-michael-k3m9qa, @carew-michael-k3m9qa,
p-k3m9qa, or #carew-family-k3m9qa for a page about a family.
See docs/research.md.
''';

const reading = {'show', 'gaps', 'find'};
const writing = {'edit', 'append', 'add-item'};
const searching = {'lookup', 'text'};

Future<void> main(List<String> arguments) async {
  final env = {...readDotEnv('.env'), ...Platform.environment};
  final parser = ArgParser()
    ..addOption(
      'tree',
      defaultsTo: env['PROSAPIA_TREE'],
      help: 'The id of a tree in Firestore.',
    )
    ..addOption('files', help: 'A tree directory, such as an export, instead.')
    ..addOption(
      'project',
      defaultsTo: env['GOOGLE_CLOUD_PROJECT'] ?? 'demo-prosapia',
      help: 'The Firebase project.',
    )
    ..addOption('bucket', help: 'Defaults to <project>.firebasestorage.app.')
    ..addOption('cache', defaultsTo: env['PROSAPIA_CACHE'] ?? '.prosapia_cache')
    ..addOption('born', help: 'find: a birth year.')
    ..addOption('within', defaultsTo: '5', help: 'find: years either side.')
    ..addOption(
      'place',
      help: 'find: part of a place name; lookup newspapers: a US state.',
    )
    ..addOption('years', help: 'lookup: a year or years, such as 1890-1900.')
    ..addOption('rows', defaultsTo: '10', help: 'lookup: how many results.')
    ..addOption(
      'context',
      defaultsTo: '3',
      help: 'text: lines either side of each match.',
    )
    ..addOption('file', help: 'edit, append: the text; add-item: the file.')
    ..addOption(
      'details',
      help:
          'add-item: the details as JSON, or a JSON file: title, date, '
          'place, transcription, notes, link, found, people.',
    )
    ..addOption(
      'based-on',
      help: 'edit: the revision the new text started from.',
    )
    ..addOption('summary', help: 'The change summary, as the history shows it.')
    ..addOption(
      'by',
      defaultsTo: env['PROSAPIA_BY'],
      help: 'The email address of the member saving the change.',
    )
    ..addOption(
      'helped-by',
      defaultsTo: Model.writer.id,
      help: 'The model that helped write the change.',
    )
    ..addFlag('apply', negatable: false, help: 'Save the change.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
    if (args.flag('help')) {
      stdout.writeln('$usage\n${parser.usage}');
      return;
    }
    final command = args.rest.firstOrNull;
    final needed = switch (command) {
      'add-item' => 1,
      'lookup' || 'text' => 3,
      _ => 2,
    };
    if (command == 'add-item'
        ? args.rest.length != 1
        : args.rest.length < needed) {
      throw const FormatException('Give a command and its arguments.');
    }
    if (!reading.contains(command) &&
        !writing.contains(command) &&
        !searching.contains(command)) {
      throw FormatException('"$command" is not a command.');
    }
    for (final (option, needed) in [
      ('file', {'edit', 'append'}),
      ('based-on', {'edit'}),
      ('summary', {'edit', 'append'}),
      ('details', {'add-item'}),
    ]) {
      if (needed.contains(command) && args[option] == null) {
        throw FormatException('$command needs --$option.');
      }
    }
    if (command == 'lookup' && !Lookup.sources.contains(args.rest[1])) {
      throw FormatException(
        'lookup searches ${Lookup.sources.join(', ')}, not ${args.rest[1]}.',
      );
    }
    if (!searching.contains(command) &&
        args['files'] == null &&
        args['tree'] == null) {
      throw const FormatException('Give --tree or --files.');
    }
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$usage\n${parser.usage}');
    exit(64);
  }

  final [command, ...words] = args.rest;
  if (searching.contains(command)) {
    exitCode = await search(command, words, args);
    return;
  }
  final project = args['project'] as String;
  FirebaseApp? app;
  final TreeStore store;
  final files = args['files'] as String?;
  if (files != null) {
    if (!Directory(files).existsSync()) {
      stderr.writeln('No such directory: $files');
      exit(66);
    }
    store = FileStore(files);
  } else {
    app = FirebaseApp.initializeApp(options: AppOptions(projectId: project));
    store = FirestoreStore(
      app,
      args['tree'] as String,
      bucketName: (args['bucket'] as String?) ?? '$project.firebasestorage.app',
      cacheDir: args['cache'] as String,
    );
  }

  try {
    final research = Research(await store.load());
    if (writing.contains(command)) {
      exitCode = await write(command, words, args, research, store);
      return;
    }
    final Object result;
    if (command == 'find') {
      final born = args['born'] as String?;
      result = research.find(
        words.join(' '),
        born: born == null ? null : int.parse(born),
        within: int.parse(args['within'] as String),
        place: args['place'] as String?,
      );
    } else {
      final page = research.pageOf(words.single);
      if (page == null) {
        stderr.writeln('No page in the tree matches ${words.single}.');
        exitCode = 1;
        return;
      }
      if (command == 'gaps' && page is! Person) {
        stderr.writeln('gaps reads a person\'s page; ${page.id} is not one.');
        exitCode = 64;
        return;
      }
      result = command == 'show'
          ? research.show(page)
          : research.gaps(page as Person);
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  } finally {
    await store.close();
    await app?.close();
  }
}

/// Runs a writing [command]: shows what it would save, and with `--apply`
/// saves it. Returns the exit code.
Future<int> write(
  String command,
  List<String> words,
  ArgResults args,
  Research research,
  TreeStore store,
) async {
  final apply = args.flag('apply');
  Member? author;
  if (apply) {
    if (!store.editable) {
      stderr.writeln('This tree is read-only here; write with --tree.');
      return 64;
    }
    final by = args['by'] as String?;
    author = by == null ? null : await store.member(by);
    if (author == null || !author.role.canEdit) {
      stderr.writeln(
        by == null
            ? 'Give --by, the email address of a member who may edit.'
            : '$by is not a member of this tree who may edit.',
      );
      return 64;
    }
  }
  final helpedBy = Model.byId(args['helped-by'] as String?)?.id;
  if (helpedBy == null && args['helped-by'] != null) {
    stderr.writeln(
      '--helped-by should be one of ${Model.all.map((m) => m.id).join(', ')}.',
    );
    return 64;
  }

  if (command == 'add-item') {
    final details = args['details'] as String;
    final NewItem item;
    try {
      final json = jsonDecode(
        details.trimLeft().startsWith('{')
            ? details
            : File(details).readAsStringSync(),
      );
      if (json is! Map<String, Object?>) {
        throw const FormatException('The details should be a JSON object.');
      }
      final file = args['file'] as String?;
      item = NewItem.read(
        research,
        json,
        file: file == null ? null : File(file),
      );
    } on FormatException catch (e) {
      stderr.writeln(e.message);
      return 65;
    } on FileSystemException catch (e) {
      stderr.writeln('${e.message}: ${e.path}');
      return 66;
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(item.toJson()));
    if (!apply) {
      stdout.writeln('\nNot saved. Run again with --apply to add it.');
      return 0;
    }
    final saved = await item.save(
      store,
      research.tree,
      author: author!,
      summary: args['summary'] as String?,
      helpedBy: helpedBy,
    );
    final change = (await store.recentChanges(
      limit: 20,
    )).where((c) => c.media.contains(saved.key)).firstOrNull;
    stdout.writeln(
      '\nAdded #${saved.key}${change == null ? '' : ' (change ${change.id})'}.',
    );
    return 0;
  }

  final page = research.pageOf(words.single);
  if (page == null) {
    stderr.writeln('No page in the tree matches ${words.single}.');
    return 1;
  }
  final text = File(args['file'] as String);
  if (!text.existsSync()) {
    stderr.writeln('No such file: ${text.path}');
    return 66;
  }
  final edit = command == 'edit'
      ? PageEdit.replace(research, page, text.readAsStringSync())
      : PageEdit.append(research, page, text.readAsStringSync());
  final basedOn = args['based-on'] == null
      ? page.revision
      : int.parse(args['based-on'] as String);
  if (!edit.changed) {
    stdout.writeln('No change to ${page.title}.');
    return 0;
  }
  stdout.writeln('${page.title} (${page.id}), revision ${page.revision}:\n');
  stdout.writeln(edit.diff());
  if (basedOn != page.revision) {
    stderr.writeln(
      '\nThe page is at revision ${page.revision}, not $basedOn: someone has '
      'changed it since. Run show again and redo the edit on its text.',
    );
    return 75;
  }
  if (edit.issues.isNotEmpty) {
    stderr.writeln('\nThe new text has problems, so it cannot be saved:');
    for (final issue in edit.issues) {
      stderr.writeln('  $issue');
    }
    return 65;
  }
  if (!apply) {
    stdout.writeln('\nNot saved. Run again with --apply to save it.');
    return 0;
  }
  final result = await edit.save(
    store,
    basedOn: basedOn,
    author: author!,
    summary: args['summary'] as String,
    helpedBy: helpedBy,
  );
  if (!result.saved) {
    stderr.writeln(
      '\nNot saved: the page moved on to revision ${result.conflictWith} '
      'while this was being written. Run show again and redo the edit.',
    );
    return 75;
  }
  final change = await store.changeOf(page.id, result.revision!);
  stdout.writeln(
    '\nSaved revision ${result.revision}'
    '${change == null ? '' : ' (change ${change.id})'}.',
  );
  return 0;
}

/// Runs `lookup` or `text`, printing JSON. Returns the exit code.
Future<int> search(String command, List<String> words, ArgResults args) async {
  final lookup = Lookup(cacheDir: args['cache'] as String);
  try {
    final rows = int.parse(args['rows'] as String);
    final years = (args['years'] as String?)?.split(RegExp(r'\s*[-–/]\s*'));
    final from = years == null ? null : int.parse(years.first);
    final to = years == null ? null : int.parse(years.last);
    final Object result;
    if (command == 'text') {
      result = await lookup.text(
        words.first,
        words.sublist(1),
        context: int.parse(args['context'] as String),
      );
    } else {
      final query = words.sublist(1).join(' ');
      result = switch (words.first) {
        'newspapers' => await lookup.newspapers(
          query,
          from: from,
          to: to,
          state: args['place'] as String?,
          rows: rows,
        ),
        'books' => await lookup.books(query, from: from, to: to, rows: rows),
        _ => await lookup.wikitree(
          query,
          born: switch (args['born']) {
            final String b => int.parse(b),
            _ => null,
          },
          rows: rows,
        ),
      };
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return 0;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 65;
  } on IOException catch (e) {
    stderr.writeln('$e');
    return 69;
  } finally {
    lookup.close();
  }
}
