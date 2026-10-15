// Converts a tree in Firestore from the earlier page format (structured
// fields and separate partnership records) to the page syntax. Each page
// gets a new revision, logged as one change, so the old text stays in each
// page's history.
//
//   dart run tool/migrate_tree.dart --project <project> --tree <tree> --by <email>

import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:prosapia/src/firestore_store.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('project', mandatory: true)
    ..addOption('tree', mandatory: true)
    ..addOption(
      'by',
      mandatory: true,
      help: 'Who to record as making the change.',
    );
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exit(64);
  }
  final project = args['project'] as String;
  final app = FirebaseApp.initializeApp(
    options: AppOptions(projectId: project),
  );
  final store = FirestoreStore(
    app,
    args['tree'] as String,
    bucketName: '$project.firebasestorage.app',
    cacheDir: '.prosapia_cache',
  );
  final count = await store.convertFromOldFormat(by: args['by'] as String);
  stdout.writeln(
    count == 0
        ? 'Nothing to convert: every page is already in the page syntax.'
        : 'Converted $count pages of tree "${args['tree']}".',
  );
  await app.close();
}
