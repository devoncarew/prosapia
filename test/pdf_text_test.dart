import 'dart:io';

import 'package:prosapia/src/images.dart';
import 'package:test/test.dart';

void main() {
  test("a PDF's own text, page by page", () async {
    final found = await pdfText(File('test/fixtures/two_pages.pdf'));
    expect(found, isNotNull);
    expect(found!.text, startsWith('— Page 1 —\n\nThomas Hughes'));
    expect(found.text, contains('— Page 2 —\n\nHe is survived'));
    expect(found.words, greaterThan(15));
  });

  test('a photo has no text of its own', () async {
    expect(await pdfText(File('spikes/image_format/input/scan_1.JPG')), isNull);
  });
}
