import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Files uploaded from the browser and not yet added to the tree. Each is
/// kept under a random token until the photos are added, and is deleted a
/// day later in any case.
class Staging {
  Staging(this.dir);

  final String dir;

  /// The largest file accepted. Cloud Run refuses larger requests.
  static const maxBytes = 32 * 1000 * 1000;

  static final _token = RegExp(r'^[0-9a-f]{20}$');

  /// Saves an uploaded file and returns its token and kind, or null if it
  /// is not a photo Prosapia can store or is too large.
  Future<({String token, String kind})?> save(Stream<List<int>> body) async {
    _clean();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) return null;
    }
    final data = bytes.takeBytes();
    final kind = kindOf(data);
    if (kind == null) return null;
    final rng = Random.secure();
    final token = List.generate(
      20,
      (_) => rng.nextInt(16).toRadixString(16),
    ).join();
    Directory(dir).createSync(recursive: true);
    File(p.join(dir, '$token.$kind')).writeAsBytesSync(data);
    return (token: token, kind: kind);
  }

  /// The file staged under [token], or null.
  File? file(String token) {
    if (!_token.hasMatch(token) || !Directory(dir).existsSync()) return null;
    for (final kind in const ['jpg', 'heic', 'png', 'tif']) {
      final f = File(p.join(dir, '$token.$kind'));
      if (f.existsSync()) return f;
    }
    return null;
  }

  /// The file as it will be stored: a JPEG or HEIC as it is, and any other
  /// scan encoded once as a JPEG.
  Future<File> archival(File staged) async {
    final ext = p.extension(staged.path).substring(1);
    if (ext == 'jpg' || ext == 'heic') return staged;
    final out = p.setExtension(staged.path, '.archival.jpg');
    // Quality 92 keeps scans visually lossless at about a third of the
    // size of quality 100; to be checked against a full-resolution scan.
    await _vips(['copy', staged.path, '$out[Q=92]']);
    return File(out);
  }

  /// A JPEG no wider than [width], for previews and for the model to read.
  Future<List<int>> preview(File staged, int width) async {
    final out = '${staged.path}.preview-$width.jpg';
    if (!File(out).existsSync()) {
      await _vips([
        'thumbnail',
        staged.path,
        '$out[Q=85,strip]',
        '$width',
        '--size',
        'down',
      ]);
    }
    return File(out).readAsBytesSync();
  }

  /// What kind of image [data] holds, by its first bytes: `jpg`, `heic`,
  /// `png` or `tif`.
  static String? kindOf(List<int> data) {
    bool starts(List<int> magic, [int at = 0]) =>
        data.length >= at + magic.length &&
        [for (var i = 0; i < magic.length; i++) data[at + i]].join(',') ==
            magic.join(',');
    if (starts([0xff, 0xd8, 0xff])) return 'jpg';
    if (starts([0x89, 0x50, 0x4e, 0x47])) return 'png';
    if (starts([0x49, 0x49, 0x2a, 0x00]) || starts([0x4d, 0x4d, 0x00, 0x2a])) {
      return 'tif';
    }
    // An ISO media file whose brand is HEIF: "ftyp" then heic, heix, mif1...
    if (starts('ftyp'.codeUnits, 4) && data.length >= 12) {
      final brand = String.fromCharCodes(data.sublist(8, 12));
      if (const {
        'heic',
        'heix',
        'heim',
        'heis',
        'mif1',
        'msf1',
      }.contains(brand)) {
        return 'heic';
      }
    }
    return null;
  }

  static Future<void> _vips(List<String> args) async {
    final result = await Process.run('vips', args);
    if (result.exitCode != 0) {
      throw StateError('vips ${args.first} failed: ${result.stderr}');
    }
  }

  /// Deletes staged files more than a day old.
  void _clean() {
    final d = Directory(dir);
    if (!d.existsSync()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    for (final f in d.listSync().whereType<File>()) {
      if (f.lastModifiedSync().isBefore(cutoff)) f.deleteSync();
    }
  }
}
