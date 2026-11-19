import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prosapia/src/lookup.dart';
import 'package:prosapia/src/research.dart';
import 'package:prosapia/src/research_write.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

/// Answers requests from [pages], by host and path, and records each URL.
Lookup _lookup(
  Map<String, Object> pages, {
  List<Uri>? asked,
  String? cacheDir,
}) => Lookup(
  client: MockClient((request) async {
    asked?.add(request.url);
    final body = pages['${request.url.host}${request.url.path}'];
    if (body == null) return http.Response('not found', 404);
    return http.Response(body is String ? body : jsonEncode(body), 200);
  }),
  cacheDir: cacheDir,
  today: DateTime(2026, 11, 19),
  pause: Duration.zero,
);

const _segment = '/service/ndnp/nn/batch/data/sn83030214/1892081401/0616.xml';

final _newspaperSearch = {
  'results': [
    {
      'title':
          'Image 18 of New-York tribune (New York [N.Y.]), August 14, 1892',
      'date': '1892-08-14',
      'id': 'http://www.loc.gov/resource/sn83030214/1892-08-14/ed-1/?sp=18',
      'location_city': ['new york'],
      'location_state': ['new york'],
      'image_url': [
        'https://tile.loc.gov/image-services/iiif/service:x:0616/full/pct:6.25/0/default.jpg#h=386&w=332',
      ],
      'word_coordinates_url':
          'https://tile.loc.gov/text-services/word-coordinates-service?q=carew',
    },
  ],
};

void main() {
  group('newspapers', () {
    test('gives each page as an item, with its passage and image', () async {
      final asked = <Uri>[];
      final found = await _lookup(
        {
          'www.loc.gov/collections/chronicling-america/': _newspaperSearch,
          'tile.loc.gov/text-services/word-coordinates-service': {
            _segment: {
              'relevant_snippet':
                  '... Patrick Nolan, Michael F. [[tag]]Carew[[/tag]],  Michael M',
            },
          },
        },
        asked: asked,
      ).newspapers('michael carew', from: 1890, to: 1900, state: 'New York');
      expect(asked.first.queryParameters, containsPair('dates', '1890/1900'));
      expect(
        asked.first.queryParameters,
        containsPair('fa', 'location_state:new york'),
      );
      expect(found.single['item'], {
        'title': 'New-York tribune (New York [N.Y.]), August 14, 1892, page 18',
        'date': '14 August 1892',
        'place': 'New York, New York',
        'link':
            'https://www.loc.gov/resource/sn83030214/1892-08-14/ed-1/?sp=18',
        'found': '19 November 2026, Chronicling America, Library of Congress',
      });
      expect(
        found.single['snippet'],
        '... Patrick Nolan, Michael F. Carew, Michael M',
      );
      expect(found.single['image'], endsWith('/full/pct:50/0/default.jpg'));
    });

    test('an item is details that add-item takes as they are', () async {
      final found = await _lookup({
        'www.loc.gov/collections/chronicling-america/': _newspaperSearch,
      }).newspapers('carew');
      final item = NewItem.read(
        Research(Tree('test')),
        found.single['item']! as Map<String, Object?>,
      );
      expect(item.details.date, '14 August 1892');
      expect(item.link, startsWith('https://www.loc.gov/resource/'));
    });
  });

  test('books narrows to texts and years, and names the volume', () async {
    final asked = <Uri>[];
    final found = await _lookup({
      'archive.org/advancedsearch.php': {
        'response': {
          'docs': [
            {
              'identifier': 'trowsgeneraldir1913p3trow',
              'title':
                  "Trow's general directory of the boroughs of Manhattan "
                  'and Bronx, city of New York',
              'volume': 'p3',
              'year': 1913,
              'publisher': ['Trow Directory Co'],
            },
          ],
        },
      },
    }, asked: asked).books('title:(directory)', from: 1910, to: 1920);
    expect(
      asked.single.queryParameters['q'],
      '(title:(directory)) AND mediatype:texts AND year:[1910 TO 1920]',
    );
    expect(found.single['item'], {
      'title':
          "Trow's general directory of the boroughs of Manhattan and "
          'Bronx, city of New York, p3',
      'date': '1913',
      'link': 'https://archive.org/details/trowsgeneraldir1913p3trow',
      'found': '19 November 2026, Internet Archive',
    });
    expect(found.single['publisher'], 'Trow Directory Co');
  });

  test('wikitree keeps only profiles with the family name given', () async {
    final found = await _lookup({
      'api.wikitree.com/api.php': [
        {
          'status': 0,
          'matches': [
            {'Id': 1, 'IsPerson': 1},
            {
              'Name': 'Carey-759',
              'FirstName': 'Mitchel',
              'LastNameAtBirth': 'Carey',
              'LastNameCurrent': 'Carey',
            },
            {
              'Name': 'Carew-483',
              'FirstName': 'Patrick',
              'LastNameAtBirth': 'Carew',
              'LastNameCurrent': 'Carew',
              'BirthDate': '1863-00-00',
              'DeathDate': '0000-00-00',
              'DeathLocation': "St John's, Newfoundland",
            },
          ],
        },
      ],
    }).wikitree('Patrick Carew', born: 1863);
    expect(found, [
      {
        'wikiTreeId': 'Carew-483',
        'name': 'Patrick Carew',
        'born': '1863',
        'deathPlace': "St John's, Newfoundland",
        'link': 'https://www.wikitree.com/wiki/Carew-483',
      },
    ]);
  });

  group('text', () {
    test('reads a newspaper page', () async {
      final found =
          await _lookup({
            'www.loc.gov/resource/sn83030214/1892-08-14/ed-1/': {
              'resource': {
                'fulltext_file':
                    'https://tile.loc.gov/text-services/word-coordinates-service?full_text=1',
              },
            },
            'tile.loc.gov/text-services/word-coordinates-service': {
              _segment: {
                'full_text':
                    'St. Anselm\'s Union\ngave a festival\nreception committee\n'
                    'Patrick Nolan, Michael F. Carew\nSTRAY DOGS',
              },
            },
          }).text(
            'https://www.loc.gov/resource/sn83030214/1892-08-14/ed-1/?sp=18&q=x',
            ['carew'],
            context: 1,
          );
      expect(found['passages'], [
        'reception committee\nPatrick Nolan, Michael F. Carew\nSTRAY DOGS',
      ]);
    });

    test('reads a book once, then from the cache', () async {
      final cache = Directory.systemTemp.createTempSync('lookup_test');
      addTearDown(() => cache.deleteSync(recursive: true));
      final pages = <String, Object>{
        'archive.org/metadata/trow1913': {
          'files': [
            {'name': 'trow1913.pdf'},
            {'name': 'trow1913_djvu.txt'},
          ],
        },
        'archive.org/download/trow1913/trow1913_djvu.txt':
            'Carew Michael F carp h1813 Crotona av\nCarey John lab',
      };
      final asked = <Uri>[];
      for (var i = 0; i < 2; i++) {
        final found = await _lookup(
          pages,
          asked: asked,
          cacheDir: cache.path,
        ).text('https://archive.org/details/trow1913', ['carew', 'mich']);
        expect(found['passages'], [
          'Carew Michael F carp h1813 Crotona av\nCarey John lab',
        ]);
      }
      expect(asked, hasLength(2));
    });

    test('refuses a link to another site', () {
      expect(
        _lookup({}).text('https://www.familysearch.org/ark:/1', ['carew']),
        throwsFormatException,
      );
    });
  });

  test('passages need every word, and join when they overlap', () {
    const text = 'a\nMichael Carew\nb\nc\nCarew, John\nd\ne\nf\ng\nCarew Wm\nh';
    expect(passages(text, ['carew'], context: 1), [
      'a\nMichael Carew\nb\nc\nCarew, John\nd',
      'g\nCarew Wm\nh',
    ]);
    expect(passages(text, ['carew', 'mich'], context: 1), [
      'a\nMichael Carew\nb\nc\nCarew, John\nd',
    ]);
    // A word matches only at the start of a word.
    expect(passages('McCarew', ['carew']), isEmpty);
  });
}
