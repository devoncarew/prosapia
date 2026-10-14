/// One line of a comparison between two versions of a page.
typedef DiffLine = ({DiffKind kind, String text});

enum DiffKind { same, removed, added }

/// Compares two texts line by line. Pages are small, so the plain
/// longest-common-subsequence table is fast enough.
List<DiffLine> diffLines(String before, String after) {
  final a = before.split('\n'), b = after.split('\n');
  final table = List.generate(
    a.length + 1,
    (_) => List.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      table[i][j] = a[i] == b[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      out.add((kind: DiffKind.same, text: a[i]));
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      out.add((kind: DiffKind.removed, text: a[i++]));
    } else {
      out.add((kind: DiffKind.added, text: b[j++]));
    }
  }
  while (i < a.length) {
    out.add((kind: DiffKind.removed, text: a[i++]));
  }
  while (j < b.length) {
    out.add((kind: DiffKind.added, text: b[j++]));
  }
  return out;
}
