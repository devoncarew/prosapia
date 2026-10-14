// Image-format spike (milestone 1 in docs/plan.md).
//
// Packages one photo (front scan, back scan, text) in each candidate format,
// then measures size, fidelity, and whether the back and the text survive.
//
// Run from this directory: dart run build.dart
// Needs: exiftool, magick, heif-enc/heif-dec/heif-info, cjxl/djxl, cwebp,
// tiffinfo, zip/unzip, sips (macOS).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const inFront = 'input/scan_1.JPG';
const inBack = 'input/scan_1_back.JPG';
const inText = 'input/scan_1.txt';
const out = 'out';

// The photo's information, taken from input/scan_1.txt.
const title = 'Susan and Michael Carew with Grandma, October 1949';
const people = ['Susan Carew', 'Michael Carew'];
const dateCreated = '1949-10';
late final String backText;

/// A string that only appears in a file if the metadata is there.
const probe = 'Susan Carew';

late final int width, height;

void main() {
  Directory(out).createSync(recursive: true);
  final lines = File(inText).readAsLinesSync();
  backText = lines.take(4).join('\n');

  final size = sh('magick', [
    'identify',
    '-format',
    '%w %h',
    inFront,
  ]).split(' ');
  width = int.parse(size[0]);
  height = int.parse(size[1]);

  // Reference pixels: the inputs as decoded today.
  sh('magick', [inFront, '$out/ref_front.png']);
  sh('magick', [inBack, '$out/ref_back.png']);

  final results = <Result>[
    twoJpegs(),
    jpegMpf(),
    tiff('tiff_lossless', ['-compress', 'zip']),
    tiff('tiff_jpeg_q90', ['-compress', 'jpeg', '-quality', '90']),
    tiff('tiff_jpeg_q75', ['-compress', 'jpeg', '-quality', '75']),
    heif('heic_q90', ['-q', '90'], 'heic'),
    heif('heic_q75', ['-q', '75'], 'heic'),
    heif('avif_q90', ['-A', '-q', '90'], 'avif'),
    heif('avif_q75', ['-A', '-q', '75'], 'avif'),
    jxlPair(),
    sideBySide('sbs_jpeg_q93', 'jpg', ['-quality', '93']),
    sideBySide('sbs_webp_q90', 'webp', ['-quality', '90']),
    sideBySide('sbs_avif_q90', 'avif', ['-quality', '90']),
    sideBySide('sbs_jxl_d1', 'jxl', ['-d', '1']),
    pdf(),
    zipBundle(),
  ];

  final inputBytes = File(inFront).lengthSync() + File(inBack).lengthSync();
  final buf = StringBuffer()
    ..writeln(
      '| Candidate | Files | Size (kB) | vs input | Front PSNR (dB) '
      '| Back PSNR (dB) | Input JPEGs recoverable exactly '
      '| Back present after metadata write | Text read back by exiftool '
      '| Text findable in raw bytes | macOS opens it '
      '| After macOS re-save: back | After macOS re-save: text |',
    )
    ..writeln('|${' --- |' * 13}');
  for (final r in results) {
    buf.writeln(
      '| ${r.name} | ${r.files.length} '
      '| ${(r.bytes / 1000).toStringAsFixed(0)} '
      '| ${(r.bytes / inputBytes * 100).toStringAsFixed(0)}% '
      '| ${r.psnrFront} | ${r.psnrBack} | ${yn(r.exact)} '
      '| ${yn(r.backAfterWrite)} | ${yn(r.textExiftool)} '
      '| ${yn(r.textRaw)} | ${yn(r.sipsOpens)} '
      '| ${r.resaveBack} | ${r.resaveText} |',
    );
  }
  File('results_table.md').writeAsStringSync(buf.toString());
  stdout.write(buf);
}

String yn(bool? b) => b == null ? 'n/a' : (b ? 'yes' : 'no');

class Result {
  Result(this.name, this.files);
  final String name;
  final List<String> files;
  String psnrFront = '', psnrBack = '';
  bool? exact, backAfterWrite, textExiftool, textRaw, sipsOpens;
  String resaveBack = 'n/a', resaveText = 'n/a';

  int get bytes => files.fold(0, (n, f) => n + File(f).lengthSync());
}

// ---------------------------------------------------------------- candidates

/// Baseline: the two input JPEGs, untouched except for added metadata.
Result twoJpegs() {
  final f = copy(inFront, '$out/two_front.jpg');
  final b = copy(inBack, '$out/two_back.jpg');
  writeMeta(f);
  writeMeta(b);
  final r = Result('Two JPEGs with metadata (baseline)', [f, b]);
  comparePixels(r, f, b);
  r.exact = true; // exiftool rewrites metadata segments only.
  r.backAfterWrite = null; // Two files: nothing holds them together.
  checkText(r, f);
  r.sipsOpens = sipsOpens(f);
  resave(r, f, 'jpeg', backCheck: (_) => 'separate file');
  return r;
}

/// The front JPEG with the back JPEG appended, indexed by a Multi-Picture
/// Format (CIPA DC-007) segment. Any JPEG reader shows the front.
Result jpegMpf() {
  final f = copy(inFront, '$out/mpf_front_tmp.jpg');
  final b = copy(inBack, '$out/mpf_back_tmp.jpg');
  writeMeta(f);
  writeMeta(b);
  final path = '$out/mpf.jpg';
  File(path).writeAsBytesSync(
    buildMpf(File(f).readAsBytesSync(), File(b).readAsBytesSync()),
  );
  final r = Result('JPEG with the back appended (MPF)', [path]);

  String? extractBack(String from, String to) {
    final res = Process.runSync('exiftool', [
      '-b',
      '-MPImage2',
      from,
    ], stdoutEncoding: null);
    final bytes = res.stdout as List<int>;
    if (bytes.isEmpty) return null;
    File(to).writeAsBytesSync(bytes);
    return to;
  }

  final back = extractBack(path, '$out/mpf_back_extracted.jpg');
  comparePixels(r, path, back);
  r.exact = back != null && sameBytes(back, b);

  // A later metadata edit by a standard tool: is the back still reachable?
  final edited = copy(path, '$out/mpf_edited.jpg');
  sh('exiftool', [
    '-q',
    '-overwrite_original',
    '-XMP-dc:Rights=A later edit by another tool',
    '-IPTC:Caption-Abstract=Added later',
    '-EXIF:Artist=Someone',
    edited,
  ]);
  final back2 = extractBack(edited, '$out/mpf_back_after_edit.jpg');
  r.backAfterWrite = back2 != null && sameBytes(back2, b);

  checkText(r, path);
  r.sipsOpens = sipsOpens(path);
  resave(
    r,
    path,
    'jpeg',
    backCheck: (p) =>
        extractBack(p, '$out/mpf_resave_back.jpg') == null ? 'lost' : 'kept',
  );
  File(f).deleteSync();
  File(b).deleteSync();
  return r;
}

/// Multi-page TIFF: page 1 the front, page 2 the back.
Result tiff(String name, List<String> compress) {
  final path = '$out/$name.tif';
  sh('magick', [inFront, inBack, ...compress, path]);
  final pagesBefore = tiffPages(path);
  writeMeta(path);
  final r = Result('Multi-page TIFF ($name)', [path]);
  sh('magick', ['$path[0]', '$out/${name}_f.png']);
  sh('magick', ['$path[1]', '$out/${name}_b.png']);
  comparePixels(r, '$out/${name}_f.png', '$out/${name}_b.png');
  r.exact = false;
  r.backAfterWrite = pagesBefore == 2 && tiffPages(path) == 2;
  checkText(r, path);
  r.sipsOpens = sipsOpens(path);
  resave(
    r,
    path,
    'tiff',
    backCheck: (p) => tiffPages(p) == 2 ? 'kept' : 'lost',
  );
  return r;
}

int tiffPages(String path) => 'TIFF Directory'
    .allMatches(Process.runSync('tiffinfo', [path]).stdout as String)
    .length;

/// HEIF container holding two images, the front as the primary item.
/// HEIC uses the HEVC codec, AVIF uses AV1.
Result heif(String name, List<String> args, String ext) {
  final path = '$out/$name.$ext';
  sh('heif-enc', [...args, inFront, inBack, '-o', path]);
  writeMeta(path);
  final r = Result('HEIF collection ($name)', [path]);
  sh('heif-dec', [path, '$out/$name.png']);
  comparePixels(r, '$out/$name-1.png', '$out/$name-2.png');
  r.exact = false;
  r.backAfterWrite = heifImages(path) == 2;
  checkText(r, path);
  r.sipsOpens = sipsOpens(path);
  resave(r, path, ext, backCheck: (p) => heifImages(p) == 2 ? 'kept' : 'lost');
  return r;
}

int heifImages(String path) => RegExp(
  r'^image:',
  multiLine: true,
).allMatches(Process.runSync('heif-info', [path]).stdout as String).length;

/// Two JPEG XL files, each a lossless repack of its input JPEG. JPEG XL has
/// no multi-page mode (only animation frames), so the pair stays two files.
Result jxlPair() {
  final f = '$out/jxl_front.jxl', b = '$out/jxl_back.jxl';
  sh('cjxl', [inFront, f]);
  sh('cjxl', [inBack, b]);
  writeMeta(f);
  writeMeta(b);
  final r = Result('Two JPEG XL files, repacked JPEGs', [f, b]);
  sh('djxl', [f, '$out/jxl_front.png']);
  sh('djxl', [b, '$out/jxl_back.png']);
  comparePixels(r, '$out/jxl_front.png', '$out/jxl_back.png');
  // The original JPEG file can be rebuilt from the JPEG XL file.
  sh('djxl', [f, '$out/jxl_front_rebuilt.jpg']);
  sh('djxl', [b, '$out/jxl_back_rebuilt.jpg']);
  r.exact =
      sameBytes('$out/jxl_front_rebuilt.jpg', inFront) &&
      sameBytes('$out/jxl_back_rebuilt.jpg', inBack);
  r.backAfterWrite = null;
  checkText(r, f);
  r.sipsOpens = sipsOpens(f);
  return r;
}

/// One image with the front on the left and the back on the right.
Result sideBySide(String name, String ext, List<String> args) {
  final path = '$out/$name.$ext';
  var decoded = path;
  if (ext == 'jxl') {
    // ImageMagick here has no JPEG XL support; go through PNG and cjxl/djxl.
    sh('magick', [inFront, inBack, '+append', '$out/${name}_src.png']);
    sh('cjxl', ['$out/${name}_src.png', path, ...args]);
    decoded = '$out/${name}_dec.png';
    sh('djxl', [path, decoded]);
  } else {
    sh('magick', [inFront, inBack, '+append', ...args, path]);
  }
  writeMeta(path);
  final r = Result('Side by side ($name)', [path]);
  sh('magick', [
    decoded,
    '-crop',
    '${width}x$height+0+0',
    '+repage',
    '$out/${name}_f.png',
  ]);
  sh('magick', [
    decoded,
    '-crop',
    '${width}x$height+$width+0',
    '+repage',
    '$out/${name}_b.png',
  ]);
  comparePixels(r, '$out/${name}_f.png', '$out/${name}_b.png');
  r.exact = false;
  r.backAfterWrite = true; // One image: the back cannot be dropped.
  checkText(r, path);
  r.sipsOpens = sipsOpens(path);
  if (ext == 'jpg' || ext == 'avif') {
    resave(r, path, ext == 'jpg' ? 'jpeg' : ext, backCheck: (_) => 'kept');
  }
  return r;
}

/// A two-page PDF with the input JPEGs embedded byte for byte.
Result pdf() {
  final path = '$out/two_page.pdf';
  File(path).writeAsBytesSync(
    buildPdf([File(inFront).readAsBytesSync(), File(inBack).readAsBytesSync()]),
  );
  writeMeta(path);
  final r = Result('Two-page PDF, JPEGs embedded', [path]);
  final bytes = File(path).readAsBytesSync();
  final hasBoth =
      contains(bytes, File(inFront).readAsBytesSync()) &&
      contains(bytes, File(inBack).readAsBytesSync());
  r.psnrFront = r.psnrBack = hasBoth ? 'identical' : 'missing';
  r.exact = hasBoth;
  r.backAfterWrite = hasBoth;
  checkText(r, path);
  r.sipsOpens = sipsOpens(path);
  return r;
}

/// A zip of the two tagged JPEGs and the text file.
Result zipBundle() {
  final path = '$out/bundle.zip';
  if (File(path).existsSync()) File(path).deleteSync();
  final f = copy(inFront, '$out/front.jpg'), b = copy(inBack, '$out/back.jpg');
  writeMeta(f);
  writeMeta(b);
  // -0: store without compression; JPEGs do not shrink and text stays plain.
  sh('zip', ['-q', '-j', '-0', path, f, b, inText]);
  final r = Result('Zip bundle: JPEGs plus text file', [path]);
  r.psnrFront = r.psnrBack = 'identical';
  r.exact = true;
  r.backAfterWrite = true;
  r.textExiftool = null; // Not an image; exiftool lists entries only.
  r.textRaw = contains(File(path).readAsBytesSync(), utf8.encode(probe));
  r.sipsOpens = false;
  File(f).deleteSync();
  File(b).deleteSync();
  return r;
}

// ------------------------------------------------------------------- checks

/// Writes the photo's information into [path] as XMP.
void writeMeta(String path) {
  sh('exiftool', [
    '-q',
    '-overwrite_original',
    '-XMP-dc:Title=$title',
    '-XMP-dc:Description=$backText',
    '-XMP-photoshop:DateCreated=$dateCreated',
    for (final p in people) '-XMP-iptcExt:PersonInImage=$p',
    path,
  ]);
}

void checkText(Result r, String path) {
  final res =
      Process.runSync('exiftool', [
            '-s3',
            '-sep',
            ';',
            '-XMP-iptcExt:PersonInImage',
            '-XMP-photoshop:DateCreated',
            '-XMP-dc:Description',
            path,
          ]).stdout
          as String;
  r.textExiftool =
      res.contains(people.join(';')) &&
      res.contains('1949:10') &&
      res.contains('with Grandma');
  r.textRaw = contains(File(path).readAsBytesSync(), utf8.encode(probe));
}

void comparePixels(Result r, String front, String? back) {
  r.psnrFront = psnr(front, '$out/ref_front.png');
  r.psnrBack = back == null ? 'missing' : psnr(back, '$out/ref_back.png');
}

/// Peak signal-to-noise ratio against the decoded input. Higher is closer;
/// above about 40 dB differences are not visible.
String psnr(String a, String b) {
  final res = Process.runSync('magick', [
    'compare',
    '-metric',
    'PSNR',
    a,
    b,
    'null:',
  ]);
  final text = (res.stderr as String).trim().split(' ').first;
  final v = double.tryParse(text);
  // ImageMagick reports identical images as inf or as its 120 dB cap.
  if (text == 'inf' || v == 0 || (v != null && v >= 100)) return 'identical';
  return v == null ? 'error' : v.toStringAsFixed(1);
}

/// Can macOS's built-in image code (used by Preview and Photos) read it?
bool sipsOpens(String path) {
  final res = Process.runSync('sips', ['-g', 'pixelWidth', path]);
  return (res.stdout as String).contains('pixelWidth:');
}

/// Re-saves [path] with macOS's built-in image code, as Preview would, then
/// checks whether the back and the text are still there.
void resave(
  Result r,
  String path,
  String format, {
  required String Function(String) backCheck,
}) {
  final ext = path.substring(path.lastIndexOf('.'));
  final to = path.replaceFirst(RegExp(r'\.\w+$'), '_resaved$ext');
  final res = Process.runSync('sips', [
    '-s',
    'format',
    format,
    path,
    '--out',
    to,
  ]);
  if (res.exitCode != 0 || !File(to).existsSync()) {
    r.resaveBack = r.resaveText = 'cannot save';
    return;
  }
  r.resaveBack = backCheck(to);
  final names =
      Process.runSync('exiftool', [
            '-s3',
            '-XMP-iptcExt:PersonInImage',
            to,
          ]).stdout
          as String;
  final desc =
      Process.runSync('exiftool', ['-s3', '-XMP-dc:Description', to]).stdout
          as String;
  final n = names.contains(people.first), d = desc.contains('Grandma');
  r.resaveText = n && d ? 'kept' : (n || d ? 'partly kept' : 'lost');
}

// ------------------------------------------------------------------ helpers

String sh(String cmd, List<String> args) {
  final res = Process.runSync(cmd, args);
  if (res.exitCode != 0) {
    stderr.writeln('FAILED: $cmd ${args.join(' ')}\n${res.stderr}');
    exit(1);
  }
  return (res.stdout as String).trim();
}

String copy(String from, String to) => File(from).copySync(to).path;

bool sameBytes(String a, String b) {
  final x = File(a).readAsBytesSync(), y = File(b).readAsBytesSync();
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

bool contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i <= hay.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Returns [front] with an MPF index segment inserted and [back] appended.
Uint8List buildMpf(Uint8List front, Uint8List back) {
  // Insert as the last application segment, after all metadata. MPF offsets
  // count from this segment, so a tool that later grows the metadata before
  // it (exiftool does not update MPF offsets) leaves the index valid.
  var pos = 2;
  while (front[pos] == 0xFF &&
      front[pos + 1] >= 0xE0 &&
      front[pos + 1] <= 0xEF) {
    pos += 2 + ((front[pos + 2] << 8) | front[pos + 3]);
  }

  const segmentLength = 2 + 4 + 82; // length field, "MPF\0", MP data
  final mpStart = pos + 2 + 2 + 4; // offsets count from the byte-order mark
  final firstSize = front.length + 2 + segmentLength;

  final d = BytesBuilder();
  void u16(int v) => d.add([v >> 8 & 0xFF, v & 0xFF]);
  void u32(int v) =>
      d.add([v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF]);

  d.add([0xFF, 0xE2]);
  u16(segmentLength);
  d.add(ascii.encode('MPF\x00'));
  d.add(ascii.encode('MM\x00*')); // big-endian TIFF-style header
  u32(8); // offset of the index IFD
  u16(3); // three entries
  u16(0xB000);
  u16(7);
  u32(4);
  d.add(ascii.encode('0100')); // MPFVersion
  u16(0xB001);
  u16(4);
  u32(1);
  u32(2); // NumberOfImages
  u16(0xB002);
  u16(7);
  u32(32);
  u32(50); // MPEntry, two 16-byte records
  u32(0); // no further IFD
  // Entry 1: the front, flagged as the representative image.
  u32(0x20030000);
  u32(firstSize);
  u32(0);
  u16(0);
  u16(0);
  // Entry 2: the back.
  u32(0x00000000);
  u32(back.length);
  u32(firstSize - mpStart);
  u16(0);
  u16(0);

  return (BytesBuilder()
        ..add(front.sublist(0, pos))
        ..add(d.toBytes())
        ..add(front.sublist(pos))
        ..add(back))
      .toBytes();
}

/// Returns a PDF with one page per JPEG, each JPEG embedded unchanged.
Uint8List buildPdf(List<Uint8List> jpegs) {
  final b = BytesBuilder();
  final offsets = <int>[];
  void obj(String head, [List<int>? stream]) {
    offsets.add(b.length);
    b.add(latin1.encode('${offsets.length} 0 obj\n$head\n'));
    if (stream != null) {
      b.add(latin1.encode('stream\n'));
      b.add(stream);
      b.add(latin1.encode('\nendstream\n'));
    }
    b.add(latin1.encode('endobj\n'));
  }

  b.add(latin1.encode('%PDF-1.4\n'));
  final n = jpegs.length;
  // Objects: 1 catalog, 2 pages, then per page: page, image, content.
  obj('<< /Type /Catalog /Pages 2 0 R >>');
  obj(
    '<< /Type /Pages /Count $n /Kids [${[for (var i = 0; i < n; i++) '${3 + i * 3} 0 R'].join(' ')}] >>',
  );
  for (var i = 0; i < n; i++) {
    final page = 3 + i * 3;
    final content = latin1.encode('q $width 0 0 $height 0 0 cm /Im0 Do Q');
    obj(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] '
      '/Resources << /XObject << /Im0 ${page + 1} 0 R >> >> '
      '/Contents ${page + 2} 0 R >>',
    );
    obj(
      '<< /Type /XObject /Subtype /Image /Width $width /Height $height '
      '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode '
      '/Length ${jpegs[i].length} >>',
      jpegs[i],
    );
    obj('<< /Length ${content.length} >>', content);
  }
  final xref = b.length;
  b.add(latin1.encode('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n'));
  for (final o in offsets) {
    b.add(latin1.encode('${o.toString().padLeft(10, '0')} 00000 n \n'));
  }
  b.add(
    latin1.encode(
      'trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    ),
  );
  return b.toBytes();
}
