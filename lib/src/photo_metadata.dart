import 'dart:io';

import 'package:path/path.dart' as p;

import 'dates.dart';
import 'tree.dart';

/// What Prosapia writes into a photo file, so a copy that leaves Prosapia
/// still says what it shows. The fields are listed in docs/media.md.
class PhotoDetails {
  PhotoDetails({
    this.title,
    this.date,
    this.place,
    this.back,
    this.people = const [],
    this.set,
    this.setIndex,
  });

  final String? title;

  /// As typed: "about 1949".
  final String? date;
  final String? place;

  /// The transcription of writing on the back.
  final String? back;

  /// Each person shown, by id and name.
  final List<({String id, String name})> people;
  final String? set;
  final int? setIndex;
}

/// The exiftool arguments that write [details] into the file stored as
/// [key]: `m-5t1q8z` for a front, `m-5t1q8z-back` for its back. Every field
/// is written, so a field left empty is cleared. People are written to the
/// front only. Only the metadata changes; the image is never re-encoded.
List<String> metadataArgs(String key, PhotoDetails details) {
  String? value(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
  final isBack = key.endsWith('-back');
  final title = value(details.title);
  final back = value(details.back);
  final place = value(details.place);
  final date = value(details.date) == null
      ? null
      : _exifDate(TreeDate.parse(details.date!));
  return [
    '-overwrite_original',
    '-XMP-dc:Identifier=${Media.idScheme}$key',
    '-XMP-dc:Title=${title ?? ''}',
    '-XMP-dc:Description=${back ?? ''}',
    '-XMP-photoshop:DateCreated=${date ?? ''}',
    place == null
        ? '-XMP-iptcExt:LocationShown='
        : '-XMP-iptcExt:LocationShown=[{LocationName=${_escape(place)}}]',
    '-XMP-dc:Relation=${details.set == null ? '' : '${Media.idScheme}set:${details.set}#${details.setIndex ?? 1}'}',
    // Repeating `=` replaces a list; an empty value alone clears it. (An
    // empty value followed by `+=` would keep the old entries.)
    if (isBack || details.people.isEmpty) ...[
      '-XMP-iptcExt:PersonInImage=',
      '-XMP-iptcExt:PersonInImageWDetails=',
    ],
    if (!isBack)
      for (final person in details.people)
        '-XMP-iptcExt:PersonInImage=${person.name}',
    if (!isBack && details.people.isNotEmpty)
      '-XMP-iptcExt:PersonInImageWDetails=[${[for (final person in details.people) '{PersonName=${_escape(person.name)},PersonId=[${Media.idScheme}${person.id}]}'].join(',')}]',
  ];
}

/// Writes [details] into [file], which is stored as [key].
Future<void> writeMetadata(File file, String key, PhotoDetails details) async {
  // An argument file keeps names and text exactly as given: no shell
  // quoting, and newlines in a transcription are written as `&#10;`.
  final args = File(p.join(file.parent.path, '.${p.basename(file.path)}.args'));
  args.writeAsStringSync(
    [
      '-E',
      ...metadataArgs(key, details).map(_escapeEntities),
      file.path,
    ].join('\n'),
  );
  try {
    final result = await Process.run('exiftool', ['-q', '-@', args.path]);
    if (result.exitCode != 0) {
      throw StateError('exiftool failed: ${result.stderr}');
    }
  } finally {
    args.deleteSync();
  }
}

/// A date for `photoshop:DateCreated`, which takes a year, a year and
/// month, or a full date, but no words. "About 1949" is written as 1949.
String? _exifDate(TreeDate date) {
  final start = date.start;
  if (start == null) return null;
  final parts = [
    start.year.toString().padLeft(4, '0'),
    if (start.month != null) start.month!.toString().padLeft(2, '0'),
    if (start.month != null && start.day != null)
      start.day!.toString().padLeft(2, '0'),
  ];
  return parts.join(':');
}

/// Escapes the characters that separate fields in an exiftool structure.
String _escape(String s) =>
    s.replaceAllMapped(RegExp(r'[,\[\]{}|]'), (m) => '|${m[0]}');

/// With `-E`, exiftool reads HTML entities in values, so a newline can be
/// given as `&#10;` in an argument file of one argument per line.
String _escapeEntities(String arg) => arg
    .replaceAll('&', '&amp;')
    .replaceAll('\r\n', '\n')
    .replaceAll('\n', '&#10;');
