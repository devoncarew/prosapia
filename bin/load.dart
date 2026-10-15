import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:prosapia/src/file_store.dart';
import 'package:prosapia/src/firestore_store.dart';
import 'package:prosapia/src/store.dart';

/// Loads a tree from files into Firestore and Cloud Storage, and names its
/// members.
///
/// An existing tree is replaced only with `--replace`, which deletes its
/// pages, history, partnerships, media records and change log first. Its
/// members are kept, and photos already in storage are not uploaded again.
Future<void> main(List<String> arguments) async {
  final env = Platform.environment;
  final parser = ArgParser()
    ..addOption(
      'tree',
      mandatory: true,
      help: 'The id to give the tree in Firestore.',
    )
    ..addMultiOption(
      'owner',
      help: 'Email address of an owner. May be repeated.',
    )
    ..addMultiOption('editor', help: 'Email address of an editor.')
    ..addMultiOption('viewer', help: 'Email address of a viewer.')
    ..addOption(
      'project',
      defaultsTo: env['GOOGLE_CLOUD_PROJECT'] ?? 'demo-prosapia',
    )
    ..addOption('bucket')
    ..addFlag(
      'replace',
      negatable: false,
      help:
          'Replace an existing tree: its pages, history and change log are '
          'deleted first. Members are kept.',
    )
    ..addOption(
      'max-file-mb',
      defaultsTo: '50',
      help: 'Larger media files are skipped.',
    );
  final ArgResults args;
  try {
    args = parser.parse(arguments);
    if (args.rest.length != 1) {
      throw const FormatException('Give one tree directory.');
    }
  } on FormatException catch (e) {
    stderr.writeln(
      '${e.message}\n\nusage: dart run prosapia:load --tree <id> --owner <email> <tree-directory>\n${parser.usage}',
    );
    exit(64);
  }
  final project = args['project'] as String;
  if (env['FIRESTORE_EMULATOR_HOST'] == null) {
    stdout.writeln(
      'Writing to the real project "$project", not the emulators.',
    );
  }

  final source = FileStore(args.rest.single);
  final tree = await source.load();
  for (final problem in tree.problems) {
    stderr.writeln('could not read $problem');
  }

  final app = FirebaseApp.initializeApp(
    options: AppOptions(projectId: project),
  );
  final store = FirestoreStore(
    app,
    args['tree'] as String,
    bucketName: (args['bucket'] as String?) ?? '$project.firebasestorage.app',
    cacheDir: '.prosapia_cache',
  );
  final treeId = args['tree'] as String;
  if (await store.exists()) {
    if (!(args['replace'] as bool)) {
      stderr.writeln(
        'Tree "$treeId" already exists in "$project". Loading again replaces its '
        'pages, their history and its change log, including any edits made '
        'since it was loaded. Rerun with --replace to do that.',
      );
      await app.close();
      exit(1);
    }
    stdout.writeln('Clearing the existing records of tree "$treeId"...');
    await store.clearRecords();
  }

  final watch = Stopwatch()..start();
  final result = await store.replaceWith(
    tree,
    source,
    maxMediaBytes: int.parse(args['max-file-mb'] as String) * 1000 * 1000,
    progress: stdout.writeln,
  );
  for (final role in Role.values) {
    for (final email in args[role.name] as List<String>) {
      await store.setMember(email, role);
      stdout.writeln('${role.name}: $email');
    }
  }
  stdout.writeln(
    'Loaded "${tree.name}" as tree "$treeId": ${result.records} records; '
    'files: ${result.uploaded} uploaded, ${result.reused} already there, '
    '${result.skipped.length} skipped; in ${watch.elapsed.inSeconds} s.',
  );
  for (final file in result.skipped) {
    stdout.writeln('  skipped, over the size limit: $file');
  }
  await app.close();
}
