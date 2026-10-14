// Checks that this machine's Google credentials can reach a real Firebase
// project's Firestore and Cloud Storage, by writing and then deleting one
// small record and one small file.
//
//   dart run tool/check_credentials.dart <project-id>

import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/check_credentials.dart <project-id>');
    exit(64);
  }
  final project = args.single;
  final app = FirebaseApp.initializeApp(
    options: AppOptions(projectId: project),
  );
  var ok = true;

  Future<void> step(String what, Future<void> Function() action) async {
    try {
      await action();
      stdout.writeln('  ok    $what');
    } catch (e) {
      ok = false;
      stdout.writeln('  FAIL  $what\n        $e');
    }
  }

  final doc = app.firestore().collection('_checks').doc('credentials');
  await step(
    'write to Firestore',
    () => doc.set({'at': DateTime.now().toIso8601String()}),
  );
  await step('read from Firestore', () async {
    if ((await doc.get()).data() == null) throw StateError('not found');
  });
  await step('delete from Firestore', doc.delete);

  final bucket = '$project.firebasestorage.app';
  final storage = app.storage().bucket(bucket).storage;
  const object = '_checks/credentials.txt';
  await step('upload to Cloud Storage', () async {
    await storage.uploadObject(
      bucket,
      object,
      Uint8List.fromList('ok'.codeUnits),
    );
  });
  await step(
    'delete from Cloud Storage',
    () => storage.deleteObject(bucket, object),
  );

  await app.close();
  stdout.writeln(ok ? 'Credentials work.' : 'Some checks failed.');
  exit(ok ? 0 : 1);
}
