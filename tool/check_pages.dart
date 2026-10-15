// Reads every page of a tree in the file layout and reports what could not
// be read, so a conversion or an import can be checked at a glance.
//
//   dart run tool/check_pages.dart <tree-directory>

import 'dart:io';

import 'package:prosapia/src/file_store.dart';
import 'package:prosapia/src/index.dart';
import 'package:prosapia/src/render.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/check_pages.dart <tree-directory>');
    exit(64);
  }
  final tree = await FileStore(args.single).load();
  final render = Renderer(tree, Index.build(tree));
  var count = 0;
  for (final p in tree.people.values) {
    final issues = [
      ...render.issuesOf(p),
      for (final d in [
        p.born?.date,
        p.christened?.date,
        p.died?.date,
        p.buried?.date,
        for (final c in p.couples) c.event.date,
        for (final f in p.facts) f.event.date,
      ].nonNulls)
        if (!d.understood) 'Date not understood: "${d.raw}"',
      for (final check in render.checksOf(p)) 'To check: $check',
    ];
    if (issues.isEmpty) continue;
    count++;
    stdout.writeln('${p.directory}:');
    for (final issue in issues) {
      stdout.writeln('  $issue');
    }
  }
  for (final problem in tree.problems) {
    stdout.writeln('could not read $problem');
  }
  stdout.writeln(
    '${tree.people.length} pages, $count with something that could not be read.',
  );
}
