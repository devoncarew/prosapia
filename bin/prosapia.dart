import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:prosapia/src/assist.dart';
import 'package:prosapia/src/auth.dart';
import 'package:prosapia/src/claude.dart';
import 'package:prosapia/src/file_store.dart';
import 'package:prosapia/src/firestore_store.dart';
import 'package:prosapia/src/images.dart';
import 'package:prosapia/src/server.dart';
import 'package:prosapia/src/store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

const usage = '''
Serve a tree from files (no sign-in; for development):
  dart run prosapia [options] <tree-directory>

Serve a tree from Firestore (members sign in with Google):
  dart run prosapia [options] --tree <tree-id>
''';

Future<void> main(List<String> arguments) async {
  // Settings in .env apply unless the environment sets them too.
  final env = {...readDotEnv('.env'), ...Platform.environment};
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: env['PORT'] ?? '8080')
    ..addOption(
      'cache',
      defaultsTo: '.prosapia_cache',
      help: 'Scratch space for display copies. Safe to delete.',
    )
    ..addOption('tree', help: 'The id of a tree in Firestore.')
    ..addOption(
      'project',
      defaultsTo: env['GOOGLE_CLOUD_PROJECT'] ?? 'demo-prosapia',
      help: 'The Firebase project.',
    )
    ..addOption(
      'bucket',
      help:
          'The Cloud Storage bucket. Defaults to <project>.firebasestorage.app.',
    )
    ..addOption(
      'web-config',
      defaultsTo: env['PROSAPIA_WEB_CONFIG'],
      help: 'Firebase web settings as JSON, for browser sign-in.',
    );
  final ArgResults args;
  try {
    args = parser.parse(arguments);
    if ((args['tree'] == null) == args.rest.isEmpty) {
      throw const FormatException('Give either a tree directory or --tree.');
    }
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$usage\n${parser.usage}');
    exit(64);
  }
  final cache = args['cache'] as String;
  final project = args['project'] as String;

  final TreeStore store;
  Sessions? sessions;
  FirebaseApp? app;
  if (args['tree'] == null) {
    final root = args.rest.single;
    if (!Directory(root).existsSync()) {
      stderr.writeln('No such directory: $root');
      exit(66);
    }
    store = FileStore(root);
  } else {
    app = FirebaseApp.initializeApp(options: AppOptions(projectId: project));
    store = FirestoreStore(
      app,
      args['tree'] as String,
      bucketName: (args['bucket'] as String?) ?? '$project.firebasestorage.app',
      cacheDir: cache,
    );
  }

  final watch = Stopwatch()..start();
  final site = await Site.load(store);
  stdout.writeln(
    'Loaded ${site.tree.people.length} people and ${site.tree.media.length} media files in ${watch.elapsedMilliseconds} ms.',
  );
  for (final problem in site.tree.problems) {
    stderr.writeln('  could not read $problem');
  }

  if (app != null) {
    final emulator = env['FIREBASE_AUTH_EMULATOR_HOST'];
    var webConfig = args['web-config'] as String?;
    final configFile = File('config/web_$project.json');
    if (webConfig == null && configFile.existsSync()) {
      webConfig = configFile.readAsStringSync();
    }
    final config = webConfig == null
        ? <String, Object?>{
            'apiKey': 'demo-key',
            'authDomain': '$project.firebaseapp.com',
            'projectId': project,
          }
        : (jsonDecode(webConfig) as Map).cast<String, Object?>();
    if (emulator == null && webConfig == null) {
      stderr.writeln(
        'Sign-in against a real project needs config/web_$project.json, '
        '--web-config or PROSAPIA_WEB_CONFIG.',
      );
      exit(64);
    }
    sessions = Sessions(
      app.auth(),
      store,
      treeName: () => site.tree.name,
      webConfig: {
        'firebase': config,
        if (emulator != null) 'authEmulator': 'http://$emulator',
      },
      secureCookies: emulator == null,
    );
  }

  // Help from Claude needs an API key; without one the editor offers none.
  final apiKey = env['ANTHROPIC_API_KEY'];
  final assistant = apiKey == null || apiKey.isEmpty
      ? null
      : Assistant(
          Claude(
            apiKey,
            baseUrl: env['ANTHROPIC_BASE_URL'] ?? 'https://api.anthropic.com',
          ),
          WritingGuide.load(),
        );

  final handler = const Pipeline()
      .addMiddleware(
        logRequests(
          logger: (message, isError) {
            if (isError) stderr.writeln(message);
          },
        ),
      )
      .addHandler(
        siteHandler(
          site,
          DisplayCopies(p.join(cache, 'display')),
          sessions: sessions,
          assistant: assistant,
        ),
      );
  // On Cloud Run the server must listen on every interface.
  final address = env.containsKey('K_SERVICE')
      ? InternetAddress.anyIPv4
      : InternetAddress.loopbackIPv4;
  final server = await io.serve(
    handler,
    address,
    int.parse(args['port'] as String),
  );
  stdout.writeln(
    'Serving ${site.tree.name} at http://localhost:${server.port}'
    '${sessions == null ? ' (from files, no sign-in)' : ' (from Firestore, sign-in required)'}',
  );
}

/// Reads `NAME=value` lines from [path], if it exists. Blank lines and lines
/// starting with `#` are skipped, and quotes around a value are removed.
Map<String, String> readDotEnv(String path) {
  final file = File(path);
  if (!file.existsSync()) return const {};
  final settings = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.trimLeft().startsWith('#')) continue;
    final m = RegExp(r'^\s*([A-Za-z_]\w*)\s*=\s*(.*?)\s*$').firstMatch(line);
    if (m == null) continue;
    var value = m[2]!;
    if (value.length >= 2 &&
        (value.startsWith('"') || value.startsWith("'")) &&
        value.endsWith(value[0])) {
      value = value.substring(1, value.length - 1);
    }
    settings[m[1]!] = value;
  }
  return settings;
}
