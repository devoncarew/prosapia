import 'dart:convert';
import 'dart:io';

import 'package:prosapia/src/photo_metadata.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('prosapia_meta'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Map<String, Object?>> read(File file) async {
    final result = await Process.run('exiftool', [
      '-json',
      '-struct',
      '-XMP:all',
      file.path,
    ]);
    return ((jsonDecode(result.stdout as String) as List).single as Map)
        .cast<String, Object?>();
  }

  Future<String> imageHash(File file) async =>
      ((await Process.run('exiftool', [
                '-s3',
                '-ImageDataHash',
                '-api',
                'ImageHashType=MD5',
                file.path,
              ])).stdout
              as String)
          .trim();

  test('details are written into the file and read back', () async {
    final file = File('${dir.path}/m-5t1q8z.jpg');
    File('spikes/image_format/input/scan_1.JPG').copySync(file.path);
    final before = file.lengthSync();
    final originalHash = await imageHash(file);
    expect(originalHash, isNotEmpty);
    await writeMetadata(
      file,
      'm-5t1q8z',
      PhotoDetails(
        title: 'Ann & Thomas, at the lake',
        date: 'about June 1949',
        place: 'Hartford, CT',
        back: 'Lake Compounce\nJune 1949',
        people: [
          (id: 'p-3f8d1a', name: 'Thomas Hughes'),
          (id: 'p-9c4e2b', name: 'Ann Price, Jr.'),
        ],
        set: 's-4h8k2m',
        setIndex: 3,
      ),
    );
    final meta = await read(file);
    expect(meta['Identifier'], 'prosapia:m-5t1q8z');
    expect(meta['Title'], 'Ann & Thomas, at the lake');
    expect(meta['Description'], 'Lake Compounce\nJune 1949');
    expect(meta['DateCreated'], '1949:06');
    expect(meta['Coverage'], 'about June 1949');
    expect(meta['LocationShown'], [
      {'LocationName': 'Hartford, CT'},
    ]);
    expect(meta['Relation'], ['prosapia:set:s-4h8k2m#3']);
    expect(meta['PersonInImage'], ['Thomas Hughes', 'Ann Price, Jr.']);
    expect(meta['PersonInImageWDetails'], [
      {
        'PersonName': 'Thomas Hughes',
        'PersonId': ['prosapia:p-3f8d1a'],
      },
      {
        'PersonName': 'Ann Price, Jr.',
        'PersonId': ['prosapia:p-9c4e2b'],
      },
    ]);
    // The image data is unchanged; only the metadata was added.
    expect(await imageHash(file), originalHash);
    expect(file.lengthSync() - before, lessThan(16000));

    // Writing again replaces the people, rather than adding to them.
    await writeMetadata(
      file,
      'm-5t1q8z',
      PhotoDetails(
        people: [
          (id: 'p-3f8d1a', name: 'Thomas Hughes'),
          (id: 'p-7k2m9x', name: 'Margaret Hughes'),
        ],
      ),
    );
    expect((await read(file))['PersonInImage'], [
      'Thomas Hughes',
      'Margaret Hughes',
    ]);

    // Writing again with fewer details clears the rest.
    await writeMetadata(file, 'm-5t1q8z', PhotoDetails(title: 'At the lake'));
    final again = await read(file);
    expect(again['Title'], 'At the lake');
    for (final cleared in [
      'Description',
      'DateCreated',
      'Coverage',
      'LocationShown',
      'Relation',
      'PersonInImage',
      'PersonInImageWDetails',
    ]) {
      expect(again.containsKey(cleared), isFalse, reason: cleared);
    }
  });

  test('a back carries the transcription but not the people', () {
    final args = metadataArgs(
      'm-5t1q8z-back',
      PhotoDetails(
        back: 'June 1949',
        people: [(id: 'p-3f8d1a', name: 'Thomas Hughes')],
      ),
    );
    expect(args, contains('-XMP-dc:Identifier=prosapia:m-5t1q8z-back'));
    expect(args, contains('-XMP-dc:Description=June 1949'));
    expect(args.where((a) => a.contains('Thomas')), isEmpty);
  });
}
