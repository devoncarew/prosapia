import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:loom/src/file_store.dart';
import 'package:loom/src/firestore_store.dart';
import 'package:loom/src/store.dart';

/// Loads a tree from files into Firestore and Cloud Storage, replacing the
/// records of the tree with the same id, and adds its first owner.
Future<void> main(List<String> arguments) async {
  final env = Platform.environment;
  final parser = ArgParser()
    ..addOption('tree', mandatory: true, help: 'The id to give the tree in Firestore.')
    ..addMultiOption('owner', help: 'Email address of an owner. May be repeated.')
    ..addMultiOption('editor', help: 'Email address of an editor.')
    ..addMultiOption('viewer', help: 'Email address of a viewer.')
    ..addOption('project', defaultsTo: env['GOOGLE_CLOUD_PROJECT'] ?? 'demo-loom')
    ..addOption('bucket')
    ..addOption('max-file-mb', defaultsTo: '50', help: 'Larger media files are skipped.');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
    if (args.rest.length != 1) throw const FormatException('Give one tree directory.');
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\nusage: dart run loom:load --tree <id> --owner <email> <tree-directory>\n${parser.usage}');
    exit(64);
  }
  final project = args['project'] as String;
  if (env['FIRESTORE_EMULATOR_HOST'] == null) {
    stdout.writeln('Writing to the real project "$project", not the emulators.');
  }

  final source = FileStore(args.rest.single);
  final tree = await source.load();
  for (final problem in tree.problems) {
    stderr.writeln('could not read $problem');
  }

  final app = FirebaseApp.initializeApp(options: AppOptions(projectId: project));
  final store = FirestoreStore(app, args['tree'] as String,
      bucketName: (args['bucket'] as String?) ?? '$project.firebasestorage.app', cacheDir: '.loom_cache');
  final watch = Stopwatch()..start();
  final result = await store.replaceWith(tree, source,
      maxMediaBytes: int.parse(args['max-file-mb'] as String) * 1000 * 1000, progress: stdout.writeln);
  for (final role in Role.values) {
    for (final email in args[role.name] as List<String>) {
      await store.setMember(email, role);
      stdout.writeln('${role.name}: $email');
    }
  }
  stdout.writeln('Loaded "${tree.name}" as tree "${args['tree']}": ${result.records} records, '
      '${result.uploaded} files uploaded, ${result.skipped} skipped, in ${watch.elapsed.inSeconds} s.');
  await app.close();
}
