import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:prosapia/src/env.dart';
import 'package:prosapia/src/file_store.dart';
import 'package:prosapia/src/firestore_store.dart';
import 'package:prosapia/src/research.dart';
import 'package:prosapia/src/store.dart';
import 'package:prosapia/src/tree.dart';

const usage = '''
Read a tree for research, from Firestore or from a tree's files. Prints JSON.

  dart run prosapia:research [options] show <id>     a page, its family and items
  dart run prosapia:research [options] gaps <id>     what a person's page lacks
  dart run prosapia:research [options] find <name>   people matching a name
      [--born <year>] [--within <years>] [--place <text>]

<id> is a page's id or reference: carew-michael-k3m9qa, @carew-michael-k3m9qa,
p-k3m9qa, or #carew-family-k3m9qa for a page about a family.
See docs/research.md.
''';

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
    ..addOption('place', help: 'find: part of a place name.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
    if (args.flag('help')) {
      stdout.writeln('$usage\n${parser.usage}');
      return;
    }
    if (args.rest.length < 2 ||
        !const {'show', 'gaps', 'find'}.contains(args.rest.first)) {
      throw const FormatException('Give a command and its argument.');
    }
    if (args['files'] == null && args['tree'] == null) {
      throw const FormatException('Give --tree or --files.');
    }
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$usage\n${parser.usage}');
    exit(64);
  }

  final [command, ...words] = args.rest;
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
