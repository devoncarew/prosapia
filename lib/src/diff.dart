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

/// A block of a page in a comparison: a fact line or a paragraph.
/// [words] is set for a block changed in place, word by word.
typedef DiffBlock = ({DiffKind kind, String text, List<DiffWord>? words});

/// A word, or the space after it, in a block changed in place.
typedef DiffWord = ({DiffKind kind, String text});

/// Compares two versions of a page block by block, for people to read: a
/// fact line or a paragraph that was edited is shown once, with the words
/// taken out and put in marked. Rewrapping a paragraph is not a change.
List<DiffBlock> diffBlocks(String before, String after) {
  final a = _blocks(before), b = _blocks(after);
  final out = <DiffBlock>[];
  final removed = <String>[], added = <String>[];
  void flush() {
    // Pair what was taken out with what was put in, in order, when they
    // are mostly the same words.
    var i = 0, j = 0;
    while (i < removed.length && j < added.length) {
      final words = _diffWords(removed[i], added[j]);
      if (_similar(words)) {
        out.add((kind: DiffKind.same, text: added[j], words: words));
        i++;
        j++;
      } else if (removed.length - i >= added.length - j) {
        out.add((kind: DiffKind.removed, text: removed[i++], words: null));
      } else {
        out.add((kind: DiffKind.added, text: added[j++], words: null));
      }
    }
    for (; i < removed.length; i++) {
      out.add((kind: DiffKind.removed, text: removed[i], words: null));
    }
    for (; j < added.length; j++) {
      out.add((kind: DiffKind.added, text: added[j], words: null));
    }
    removed.clear();
    added.clear();
  }

  for (final line in _lcs(a.map(_key).toList(), b.map(_key).toList())) {
    switch (line.kind) {
      case DiffKind.same:
        flush();
        out.add((kind: DiffKind.same, text: b[line.j], words: null));
      case DiffKind.removed:
        removed.add(a[line.i]);
      case DiffKind.added:
        added.add(b[line.j]);
    }
  }
  flush();
  return out;
}

/// The fact lines of a page, one block each, then its paragraphs.
List<String> _blocks(String source) {
  final blocks = <String>[];
  final paragraphs = source
      .replaceAll('\r\n', '\n')
      .trim()
      .split(RegExp(r'\n[ \t]*\n\s*'));
  for (final (i, p) in paragraphs.indexed) {
    if (i == 0 && RegExp(r'^\s*Name\s*:', caseSensitive: false).hasMatch(p)) {
      blocks.addAll(p.split('\n'));
    } else if (p.trim().isNotEmpty) {
      blocks.add(p);
    }
  }
  return blocks;
}

/// A block as compared: its words, whatever the spacing.
String _key(String block) => block.trim().split(RegExp(r'\s+')).join(' ');

bool _similar(List<DiffWord> words) {
  var same = 0, total = 0;
  for (final w in words) {
    if (w.text.trim().isEmpty) continue;
    total++;
    if (w.kind == DiffKind.same) same++;
  }
  return total > 0 && same * 2 >= total - same;
}

/// The words of [after], with those from [before] that were taken out,
/// marked. The spaces between words are kept as in [after].
List<DiffWord> _diffWords(String before, String after) {
  final a = before.trim().split(RegExp(r'\s+'));
  final bParts = RegExp(r'\S+|\s+').allMatches(after.trim()).map((m) => m[0]!);
  final b = [for (final p in bParts) p];
  final bWords = [
    for (final p in b)
      if (p.trim().isNotEmpty) p,
  ];
  final out = <DiffWord>[];
  // Spaces in [after] follow its words, so they are added after each word.
  final spaces = <String>[];
  for (var k = 0; k < b.length; k++) {
    if (b[k].trim().isNotEmpty) {
      spaces.add(k + 1 < b.length && b[k + 1].trim().isEmpty ? b[k + 1] : '');
    }
  }
  for (final step in _lcs(a, bWords)) {
    switch (step.kind) {
      case DiffKind.removed:
        out.add((kind: DiffKind.removed, text: '${a[step.i]} '));
      case DiffKind.same || DiffKind.added:
        out.add((kind: step.kind, text: bWords[step.j]));
        if (spaces[step.j].isNotEmpty) {
          out.add((kind: DiffKind.same, text: spaces[step.j]));
        }
    }
  }
  return out;
}

/// The longest-common-subsequence steps from [a] to [b], with the index
/// in each that a step refers to.
List<({DiffKind kind, int i, int j})> _lcs(List<String> a, List<String> b) {
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
  final out = <({DiffKind kind, int i, int j})>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      out.add((kind: DiffKind.same, i: i++, j: j++));
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      out.add((kind: DiffKind.removed, i: i++, j: j));
    } else {
      out.add((kind: DiffKind.added, i: i, j: j++));
    }
  }
  while (i < a.length) {
    out.add((kind: DiffKind.removed, i: i++, j: j));
  }
  while (j < b.length) {
    out.add((kind: DiffKind.added, i: i, j: j++));
  }
  return out;
}
