import 'dart:io';

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
