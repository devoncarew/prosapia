import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:prosapia/src/export.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  test('removes the folder of a renamed page, and keeps the rest', () {
    final checkout = Directory.systemTemp.createTempSync('export_test');
    addTearDown(() => checkout.deleteSync(recursive: true));
    for (final name in [
      'davidson-allan-maclean-7ms37m',
      'davidson-allan-mclean-7ms37m',
      'carew-michael-k3m9qa',
      'gone-zzzzzz',
    ]) {
      Directory(
        p.join(checkout.path, 'people', name),
      ).createSync(recursive: true);
    }
    final tree = Tree('test')
      ..people['p-7ms37m'] = Person.fromSource(
        'p-7ms37m',
        'davidson-allan-mclean-7ms37m',
        'Name: Allan McLean Davidson\n',
      )
      ..people['p-k3m9qa'] = Person.fromSource(
        'p-k3m9qa',
        'carew-michael-k3m9qa',
        'Name: Michael Carew\n',
      );

    expect(removeRenamed(checkout.path, tree), 1);
    expect(
      [
        for (final d in Directory(p.join(checkout.path, 'people')).listSync())
          p.basename(d.path),
      ]..sort(),
      ['carew-michael-k3m9qa', 'davidson-allan-mclean-7ms37m', 'gone-zzzzzz'],
    );
  });
}
