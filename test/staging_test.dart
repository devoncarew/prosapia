import 'dart:convert';
import 'dart:io';

import 'package:prosapia/src/staging.dart';
import 'package:test/test.dart';

void main() {
  test('files are recognised by their first bytes', () {
    expect(Staging.kindOf([0xff, 0xd8, 0xff, 0xe0]), 'jpg');
    expect(Staging.kindOf('%PDF-1.7\n'.codeUnits), 'pdf');
    expect(Staging.kindOf([0x89, 0x50, 0x4e, 0x47, 0x0d]), 'png');
    expect(Staging.kindOf('PK\x03\x04'.codeUnits), isNull);
    expect(Staging.kindOf('%PD'.codeUnits), isNull);
  });

  group('a PDF of one scan', () {
    final jpeg = File('spikes/image_format/input/scan_1.JPG').readAsBytesSync();

    /// A PDF of [pages] pages showing [jpeg], with no cross-reference table,
    /// as some scanners write them.
    List<int> pdf({
      bool lengthByReference = false,
      int pages = 1,
      String extra = '',
    }) {
      final head = latin1.encode(
        '%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'
        '2 0 obj << /Type /Pages /Count $pages >> endobj\n'
        '${[for (var i = 0; i < pages; i++) '${3 + i} 0 obj << /Type /Page /Parent 2 0 R $extra>> endobj\n'].join()}'
        '9 0 obj << /Type /XObject /Subtype /Image /Width 10 /Height 10 '
        '/Filter /DCTDecode /Length ${lengthByReference ? '10 0 R' : jpeg.length} >>\nstream\r\n',
      );
      return [
        ...head,
        ...jpeg,
        ...latin1.encode(
          '\r\nendstream\nendobj\n10 0 obj ${jpeg.length} endobj\n%%EOF\n',
        ),
      ];
    }

    test('is its JPEG, unchanged', () {
      expect(Staging.scanInPdf(pdf()), jpeg);
      expect(Staging.scanInPdf(pdf(lengthByReference: true)), jpeg);
      // Lines ended by a carriage return alone, as one scanner writes them.
      expect(
        Staging.scanInPdf(
          latin1.encode(
            latin1.decode(pdf()).replaceFirst('stream\r\n', 'stream\r'),
          ),
        ),
        jpeg,
      );
    });

    test('unless there is more to the PDF', () {
      expect(Staging.scanInPdf(pdf(pages: 2)), isNull);
      expect(
        Staging.scanInPdf(pdf(extra: '/Resources << /Font << >> >> ')),
        isNull,
      );
    });
  });
}
