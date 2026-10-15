// Converts a tree directory from the earlier format (YAML front matter and a
// unions/ directory) to the page syntax, in place.
//
//   dart run tool/convert_tree.dart <tree-directory>

import 'dart:io';

import 'package:prosapia/src/legacy.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/convert_tree.dart <tree-directory>');
    exit(64);
  }
  stdout.writeln('Converted ${convertLegacyTreeDir(args.single)} pages.');
}
