import 'package:prosapia/src/diff.dart';
import 'package:test/test.dart';

void main() {
  test('an edited paragraph is shown once, with the words marked', () {
    final blocks = diffBlocks(
      'Name: A\n\nHe kept a hardware store\nfor forty years.\n\nLater.',
      'Name: A\n\nHe kept a large hardware store for\nforty years.\n\nLater.',
    );
    expect(blocks, hasLength(3));
    final words = blocks[1].words!;
    expect(words.where((w) => w.kind == DiffKind.added).map((w) => w.text), [
      'large',
    ]);
    expect(words.where((w) => w.kind == DiffKind.removed), isEmpty);
  });

  test('rewrapping a paragraph is not a change', () {
    final blocks = diffBlocks(
      'Name: A\n\nOne two\nthree.',
      'Name: A\n\nOne\ntwo three.',
    );
    expect(
      blocks.every((b) => b.kind == DiffKind.same && b.words == null),
      isTrue,
    );
  });

  test('fact lines are compared one by one', () {
    final blocks = diffBlocks(
      'Name: A\nBorn: 1900',
      'Name: A\nBorn: 1901\nDied: 1980',
    );
    expect(blocks.map((b) => (b.kind, b.words != null)), [
      (DiffKind.same, false),
      (DiffKind.same, true),
      (DiffKind.added, false),
    ]);
  });

  test('an unrelated paragraph is taken out and put in', () {
    final blocks = diffBlocks(
      'Name: A\n\nApples and pears.',
      'Name: A\n\nA trip to Wales.',
    );
    expect(blocks.map((b) => b.kind), [
      DiffKind.same,
      DiffKind.removed,
      DiffKind.added,
    ]);
  });
}
