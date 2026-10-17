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

  /// A JPEG of [media], made from its [original] file, no wider than the nearest allowed width to [width],
  /// or null if it cannot be made.
  Future<File?> get(Media media, File original, int width) {
    final w = widths.firstWhere((x) => x >= width, orElse: () => widths.last);
    final stamp = original.lastModifiedSync().millisecondsSinceEpoch;
    final out = p.join(cacheDir, '${media.key}-$w-$stamp.jpg');
    if (File(out).existsSync()) return Future.value(File(out));
    // The callback must not return the removed future: whenComplete would
    // wait on it, and it is this same future.
    return _inProgress[out] ??= _make(original.path, out, w).whenComplete(() {
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

/// The number of pages in the PDF [pdf]; 1 if it cannot be read.
Future<int> pageCount(File pdf) async {
  final result = await Process.run('vipsheader', ['-f', 'n-pages', pdf.path]);
  return int.tryParse('${result.stdout}'.trim()) ?? 1;
}

/// A JPEG of page [page], counted from 1, of the PDF [pdf], no larger than
/// [size] on either side; null if it cannot be made. Made each time it is
/// asked for: it is for the model to read, not to show.
Future<List<int>?> pdfPage(File pdf, int page, int size) async {
  final work = Directory.systemTemp.createTempSync('prosapia_page');
  try {
    final out = p.join(work.path, 'page.jpg');
    final result = await Process.run('vips', [
      'thumbnail',
      '${pdf.path}[page=${page - 1}]',
      '$out[Q=85,strip]',
      '$size',
      '--height',
      '$size',
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('page $page of ${pdf.path} failed: ${result.stderr}');
      return null;
    }
    return File(out).readAsBytesSync();
  } finally {
    work.deleteSync(recursive: true);
  }
}
