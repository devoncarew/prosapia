import 'dart:io';

import 'package:args/args.dart';
import 'package:loom/src/images.dart';
import 'package:loom/src/index.dart';
import 'package:loom/src/server.dart';
import 'package:loom/src/tree.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080')
    ..addOption('cache',
        defaultsTo: '.loom_cache',
        help: 'Where the index and display copies go. Safe to delete.');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
    if (args.rest.length != 1) throw const FormatException('expected one tree directory');
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\nusage: dart run loom [options] <tree-directory>\n${parser.usage}');
    exit(64);
  }
  final root = args.rest.single;
  if (!Directory(root).existsSync()) {
    stderr.writeln('No such directory: $root');
    exit(66);
  }
  final cache = args['cache'] as String;

  final watch = Stopwatch()..start();
  final tree = await Tree.load(root);
  final index = Index.build(tree, p.join(cache, 'index.db'));
  stdout.writeln('Loaded ${tree.people.length} people, ${tree.unions.length} partnerships '
      'and ${tree.media.length} media files in ${watch.elapsedMilliseconds} ms.');
  for (final problem in tree.problems) {
    stderr.writeln('  could not read $problem');
  }

  final handler = const Pipeline()
      .addMiddleware(logRequests(logger: (message, isError) {
        if (isError) stderr.writeln(message);
      }))
      .addHandler(siteHandler(tree, index, DisplayCopies(p.join(cache, 'display'))));
  final server = await io.serve(handler, InternetAddress.loopbackIPv4, int.parse(args['port'] as String));
  stdout.writeln('Serving ${tree.name} at http://localhost:${server.port}');
}
