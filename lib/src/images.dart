import 'dart:io';

import 'package:path/path.dart' as p;

import 'tree.dart';

/// Makes resized web copies of stored images on demand. Copies are never
/// committed; the cache directory can be deleted at any time.
class DisplayCopies {
  DisplayCopies(this.cacheDir);

  final String cacheDir;

  static const widths = [240, 480, 960, 1920];

  final _inProgress = <String, Future<File?>>{};

  /// A JPEG of [media] no wider than the nearest allowed width to [width],
  /// or null if it cannot be made.
  Future<File?> get(Media media, int width) {
    final w = widths.firstWhere((x) => x >= width, orElse: () => widths.last);
    final stamp = File(media.path).lastModifiedSync().millisecondsSinceEpoch;
    final out = p.join(cacheDir, '${media.key}-$w-$stamp.jpg');
    if (File(out).existsSync()) return Future.value(File(out));
    // The callback must not return the removed future: whenComplete would
    // wait on it, and it is this same future.
    return _inProgress[out] ??= _make(media.path, out, w).whenComplete(() {
      _inProgress.remove(out);
    });
  }

  Future<File?> _make(String source, String out, int width) async {
    Directory(cacheDir).createSync(recursive: true);
    // Write to a temporary name so a half-written file is never served.
    final tmp = '$out.tmp.jpg';
    final result = await Process.run('vips', [
      'thumbnail', source, '$tmp[Q=85,strip]', '$width',
      '--size', 'down', // never enlarge
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('display copy failed for $source: ${result.stderr}');
      return null;
    }
    return File(tmp).renameSync(out);
  }
}
