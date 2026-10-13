// Firebase spike (milestone 3 in docs/plan.md).
//
// Checks that a Dart server can do what Loom needs from Firebase, using the
// official Admin SDK against the local emulators:
//   1. Firestore: write and read a page, keep revisions, refuse a stale save.
//   2. Sign-in: verify a Google sign-in and keep it as a session cookie.
//   3. Cloud Storage: store a photo and get the same bytes back.
//
// Run from the repository root:
//   firebase emulators:exec "dart run spikes/firebase/spike.dart"

import 'dart:convert';
import 'dart:io';

import 'package:firebase_admin_sdk/auth.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:google_cloud_storage/google_cloud_storage.dart' as gcs;
import 'package:http/http.dart' as http;

const project = 'demo-loom';
var failures = 0;

void check(String what, bool ok, [Object? detail]) {
  stdout.writeln('  ${ok ? 'ok  ' : 'FAIL'}  $what${detail == null ? '' : '  ($detail)'}');
  if (!ok) failures++;
}

Future<void> main() async {
  for (final name in ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST', 'FIREBASE_STORAGE_EMULATOR_HOST']) {
    if (Platform.environment[name] == null) {
      stderr.writeln('$name is not set. Run this under "firebase emulators:exec".');
      exit(64);
    }
  }
  final app = FirebaseApp.initializeApp(options: AppOptions(projectId: project));

  await firestore(app);
  await signIn(app);
  await storage(app);

  await app.close();
  stdout.writeln(failures == 0 ? '\nAll checks passed.' : '\n$failures checks failed.');
  exit(failures == 0 ? 0 : 1);
}

Future<void> firestore(FirebaseApp app) async {
  stdout.writeln('Firestore');
  final db = app.firestore();
  final tree = db.collection('trees').doc('spike');
  final person = tree.collection('people').doc('p-7k2m9x');

  // A page with nested structured facts and a markdown body.
  await person.set({
    'name': 'Margaret Ellen Hughes',
    'born': {'date': '1887-03-14', 'place': 'Scranton, Pennsylvania'},
    'parents': ['p-3f8d1a', 'p-9c4e2b'],
    'body': 'Margaret grew up above the store.',
    'revision': 1,
  });
  final read = (await person.get()).data()!;
  check('write and read a page with nested facts',
      read['name'] == 'Margaret Ellen Hughes' && (read['born'] as Map)['date'] == '1887-03-14' && (read['parents'] as List).length == 2);

  // A save: new revision document, page updated, change logged, all or nothing.
  Future<bool> save(int basedOn, String body, String author, String summary) {
    return db.runTransaction((tx) async {
      final current = (await tx.get(person)).data()!;
      final revision = current['revision'] as int;
      if (revision != basedOn) return false; // someone else saved first
      tx.update(person, {'body': body, 'revision': revision + 1});
      tx.set(person.collection('revisions').doc('${revision + 1}'),
          {'body': body, 'author': author, 'summary': summary, 'at': FieldValue.serverTimestamp});
      tx.set(tree.collection('changes').doc(), {
        'author': author, 'summary': summary, 'pages': ['p-7k2m9x'], 'at': FieldValue.serverTimestamp, //
      });
      return true;
    });
  }

  check('a save writes a revision and a change-log entry in one transaction',
      await save(1, 'Margaret grew up above her father\'s hardware store.', 'devon', 'Add the store'));
  check('a save based on a stale revision is refused', !await save(1, 'Overwrite!', 'someone', 'Stale'));

  final after = (await person.get()).data()!;
  check('the page holds the accepted text', after['revision'] == 2 && (after['body'] as String).contains('hardware'));
  final revisions = await person.collection('revisions').orderBy('at', descending: true).get();
  check('history lists revisions, newest first',
      revisions.docs.length == 1 && revisions.docs.first.data()['author'] == 'devon', '${revisions.docs.length} revision');
  final at = revisions.docs.first.data()['at'];
  check('server timestamps come back as timestamps', at is Timestamp, at.runtimeType);

  // Loading a whole tree: batch-write 500 people, read them back in one query.
  final watch = Stopwatch()..start();
  final batch = db.batch();
  for (var i = 0; i < 500; i++) {
    batch.set(tree.collection('load').doc('p-$i'), {'name': 'Person $i', 'parents': ['p-${i ~/ 2}']});
  }
  await batch.commit();
  final wrote = watch.elapsedMilliseconds;
  watch.reset();
  final all = await tree.collection('load').get();
  check('batch-write 500 documents and load them in one query', all.docs.length == 500, 'write $wrote ms, read ${watch.elapsedMilliseconds} ms');

  final found = await tree.collection('load').where('parents', WhereFilter.arrayContains, 'p-7').get();
  check('query children by parent id', found.docs.length == 2, found.docs.map((d) => d.id).join(', '));
}

Future<void> signIn(FirebaseApp app) async {
  stdout.writeln('Sign-in');
  final auth = app.auth();
  final host = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];

  // What the browser does: sign in with Google and receive an ID token. The
  // emulator accepts a made-up Google identity in place of a real one.
  final googleIdentity = jsonEncode({'sub': 'google-uid-123', 'email': 'relative@example.com', 'email_verified': true, 'name': 'A Relative'});
  final response = await http.post(
    Uri.parse('http://$host/identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=fake-api-key'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'postBody': 'id_token=${Uri.encodeQueryComponent(googleIdentity)}&providerId=google.com',
      'requestUri': 'http://localhost',
      'returnSecureToken': true,
    }),
  );
  final idToken = (jsonDecode(response.body) as Map)['idToken'] as String?;
  check('the emulator signs a Google account in', idToken != null, response.statusCode);
  if (idToken == null) return;

  // What the server does with it.
  final decoded = await auth.verifyIdToken(idToken);
  check('the server verifies the sign-in and reads the email', decoded.email == 'relative@example.com', decoded.email);
  check('the sign-in provider is Google', decoded.firebase.signInProvider == 'google.com', decoded.firebase.signInProvider);

  final cookie = await auth.createSessionCookie(idToken, SessionCookieOptions(expiresIn: const Duration(days: 5).inMilliseconds));
  final session = await auth.verifySessionCookie(cookie);
  check('a session cookie is created and verified', session.uid == decoded.uid, '${cookie.length} characters');

  // The emulator issues unsigned tokens, so a forged signature cannot be
  // tested here; that check needs a real project (milestone 5). A token that
  // is not a token at all must still be refused.
  try {
    await auth.verifyIdToken('not-a-token');
    check('a malformed token is rejected', false);
  } catch (e) {
    check('a malformed token is rejected', true, e.runtimeType);
  }

  final user = await auth.getUserByEmail('relative@example.com');
  check('look up a member by email', user.uid == decoded.uid, user.displayName);
}

Future<void> storage(FirebaseApp app) async {
  stdout.writeln('Cloud Storage');
  final bucket = app.storage().bucket('$project.firebasestorage.app');
  final photo = File('spikes/image_format/input/scan_1.JPG').readAsBytesSync();
  const path = 'trees/spike/media/m-5t1q8z.jpg';

  await bucket.storage.uploadObject(bucket.name, path, photo, metadata: gcs.ObjectMetadata(contentType: 'image/jpeg'));
  final meta = await bucket.storage.objectMetadata(bucket.name, path);
  check('upload a photo', meta.size == BigInt.from(photo.length), '${meta.size} bytes, ${meta.contentType}');

  final back = await bucket.storage.downloadObject(bucket.name, path);
  var same = back.length == photo.length;
  for (var i = 0; same && i < photo.length; i++) {
    same = back[i] == photo[i];
  }
  check('download returns the same bytes, so embedded metadata survives', same);

  await bucket.storage.deleteObject(bucket.name, path);
}
