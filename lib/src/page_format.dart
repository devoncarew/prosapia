import 'fact_format.dart';
import 'page_syntax.dart';

/// The width prose is wrapped to.
const pageWidth = 88;

/// Writes a page in its normal form, so that pages that read the same are
/// written the same: fact lines with their parts quoted and labelled where
/// that makes them read reliably (see fact_format.dart), one blank line between
/// blocks, and paragraphs and list items wrapped at [width] columns. What
/// the page says, and how it renders, is unchanged. Code, tables, quotes
/// and HTML are left as written.
///
/// Formatting is stable: a formatted page formats to itself.
String formatPage(String source, {int width = pageWidth}) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  var i = 0;
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  final out = <String>[];
  if (i < lines.length &&
      ParsedPage.labelPattern.firstMatch(lines[i])?[1]?.toLowerCase() ==
          'name') {
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      // A fact and the indented lines that carry it on.
      var end = i + 1;
      while (end < lines.length &&
          lines[end].trim().isNotEmpty &&
          ParsedPage.continues(lines[end])) {
        end++;
      }
      final m = ParsedPage.labelPattern.firstMatch(lines[i]);
      if (m == null) {
        out.addAll([for (final line in lines.sublist(i, end)) _spaces(line)]);
      } else {
        final value = [
          m[2]!,
          ...lines.sublist(i + 1, end),
        ].map(_spaces).where((v) => v.isNotEmpty).join(' ');
        out.addAll(formatFact(_spaces(m[1]!), value, width: width));
      }
      i = end;
    }
  }
  final body = _Body(width).format(lines.sublist(i));
  if (body.isNotEmpty) {
    if (out.isNotEmpty) out.add('');
    out.addAll(body);
  }
  return out.isEmpty ? '' : '${out.join('\n')}\n';
}

/// [s] trimmed, with runs of spaces made one.
String _spaces(String s) => s.trim().replaceAll(RegExp(r'[ \t]+'), ' ');

final _fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
final _heading = RegExp(r'^\s{0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*$');
final _item = RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])(?:[ \t]+(.*))?$');
final _rule = RegExp(r'^\s{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');
final _setext = RegExp(r'^\s{0,3}(=+|-+)[ \t]*$');

/// The markdown below the facts.
class _Body {
  _Body(this.width);

  final int width;
  final out = <String>[];

  List<String> format(List<String> lines) {
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      if (_fence.firstMatch(line) case final m?) {
        // A fenced code block, as written, to its closing fence.
        final fence = m[1]!;
        _block([line.trimRight()]);
        for (i++; i < lines.length; i++) {
          out.add(lines[i].trimRight());
          if (lines[i].trim().startsWith(fence[0] * fence.length)) break;
        }
        i++;
        continue;
      }
      if (_heading.firstMatch(line) case final m?) {
        _block(['${m[1]}${m[2] == null ? '' : ' ${_spaces(m[2]!)}'}']);
        i++;
        continue;
      }
      if (_rule.hasMatch(line)) {
        _block([line.trim()]);
        i++;
        continue;
      }
      if (_verbatim(line)) {
        // Quotes, tables, HTML and indented code: kept as written.
        final block = <String>[];
        for (; i < lines.length && lines[i].trim().isNotEmpty; i++) {
          block.add(lines[i].trimRight());
        }
        _block(block);
        continue;
      }
      if (_item.hasMatch(line)) {
        final block = <String>[];
        while (i < lines.length && lines[i].trim().isNotEmpty) {
          final m = _item.firstMatch(lines[i])!;
          final text = [if (m[3] != null) m[3]!];
          for (i++; i < lines.length && _continues(lines[i]); i++) {
            text.add(lines[i]);
          }
          block.addAll(
            _wrap(
              text,
              '${m[1]}${m[2]} ',
              ' ' * (m[1]!.length + m[2]!.length + 1),
            ),
          );
          if (i < lines.length && !_item.hasMatch(lines[i])) break;
        }
        _block(block);
        continue;
      }
      // A paragraph, to the next blank line or block.
      final text = [line];
      for (i++; i < lines.length && _continues(lines[i]); i++) {
        text.add(lines[i]);
      }
      if (i < lines.length && _setext.hasMatch(lines[i])) {
        // A heading underlined with === or ---: kept as written.
        _block([...text.map((l) => l.trimRight()), lines[i].trim()]);
        i++;
        continue;
      }
      _block(_wrap(text, '', ''));
    }
    return out;
  }

  /// Adds [lines] as a block, after a blank line.
  void _block(List<String> lines) {
    if (out.isNotEmpty) out.add('');
    out.addAll(lines);
  }

  static bool _verbatim(String line) {
    final t = line.trimLeft();
    return t.startsWith('>') ||
        t.startsWith('|') ||
        t.startsWith('<') ||
        line.startsWith('    ') ||
        line.startsWith('\t');
  }

  /// Whether [line] carries on the paragraph or list item above it.
  static bool _continues(String line) =>
      line.trim().isNotEmpty &&
      !_item.hasMatch(line) &&
      _heading.firstMatch(line) == null &&
      _fence.firstMatch(line) == null &&
      !_rule.hasMatch(line) &&
      !_setext.hasMatch(line) &&
      !line.trimLeft().startsWith('>') &&
      !line.trimLeft().startsWith('|');

  /// [lines] of one paragraph, wrapped: the first line starts with [first]
  /// and the rest with [rest]. A hard line break (two spaces or a backslash
  /// at the end of a line) is kept.
  List<String> _wrap(List<String> lines, String first, String rest) {
    final result = <String>[];
    var words = <String>[];
    void flush(String end) {
      final wrapped = _fill(words, width - rest.length);
      for (var k = 0; k < wrapped.length; k++) {
        final prefix = result.isEmpty && k == 0 ? first : rest;
        result.add('$prefix${wrapped[k]}${k == wrapped.length - 1 ? end : ''}');
      }
      words = [];
    }

    for (var k = 0; k < lines.length; k++) {
      final line = lines[k];
      words.addAll(_words(line));
      if (k == lines.length - 1) break;
      if (line.endsWith('  ') && line.trim().isNotEmpty) {
        flush('  ');
      } else if (line.trimRight().endsWith(r'\')) {
        flush('');
      }
    }
    flush('');
    return result;
  }

  /// Fills lines up to [width] with [words]. A word that would start a
  /// line and be read as markdown there (`#`, `-`, `1.`) stays on the line
  /// before, even if that makes it long.
  static List<String> _fill(List<String> words, int width) {
    final lines = <String>[];
    var line = '';
    for (final word in words) {
      if (line.isEmpty) {
        line = word;
      } else if (line.length + 1 + word.length <= width || _unsafe(word)) {
        line = '$line $word';
      } else {
        lines.add(line);
        line = word;
      }
    }
    if (line.isNotEmpty || lines.isEmpty) lines.add(line);
    return lines;
  }

  static final _unsafePattern = RegExp(
    r'^(#{1,6}|[-*+=]+|>.*|\d{1,9}[.)]|`{3,}.*|~{3,}.*|<.*)$',
  );
  static bool _unsafe(String word) => _unsafePattern.hasMatch(word);

  /// The words of [line]. Links, `[date: …]` and `[place: …]` marks and
  /// code are kept whole, so none is split across lines.
  static List<String> _words(String line) {
    final words = <String>[];
    final sb = StringBuffer();
    var brackets = 0, parens = 0;
    String? code;
    final text = line.trim().replaceAll('\t', ' ');
    for (var k = 0; k < text.length; k++) {
      final c = text[k];
      if (code != null) {
        if (text.startsWith(code, k)) {
          sb.write(code);
          k += code.length - 1;
          code = null;
        } else {
          sb.write(c);
        }
        continue;
      }
      if (c == '`') {
        var n = 1;
        while (k + n < text.length && text[k + n] == '`') {
          n++;
        }
        if (text.indexOf('`' * n, k + n) > 0) code = '`' * n;
        sb.write('`' * n);
        k += n - 1;
        continue;
      }
      if (c == '[') brackets++;
      if (c == ']' && brackets > 0) brackets--;
      // A link's address: the parentheses right after `]`.
      if (c == '(' && (parens > 0 || (k > 0 && text[k - 1] == ']'))) parens++;
      if (c == ')' && parens > 0) parens--;
      if (c == ' ') {
        if (brackets > 0 || parens > 0) {
          // Inside a link or mark, runs of spaces are made one.
          if (!sb.toString().endsWith(' ')) sb.write(c);
        } else if (sb.isNotEmpty) {
          words.add(sb.toString());
          sb.clear();
        }
      } else {
        sb.write(c);
      }
    }
    if (sb.isNotEmpty) words.add(sb.toString());
    return words;
  }
}
