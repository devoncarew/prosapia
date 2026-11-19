import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'dates.dart';

/// Searches of the free sources an agent may search itself, for
/// `prosapia:research lookup` and `text`. Each newspaper or book found is a
/// candidate whose `item` is the details `add-item` takes as they are; a
/// WikiTree profile is a lead, not an item, since a tree is not a source.
///
/// Requests are few and at least a second apart, as each site asks.
class Lookup {
  Lookup({http.Client? client, this.cacheDir, DateTime? today, this.pause})
    : _client = client ?? http.Client(),
      _today = today ?? DateTime.now();

  final http.Client _client;
  final DateTime _today;

  /// Where book texts are kept once fetched, so a second search of the same
  /// book does not fetch it again.
  final String? cacheDir;

  /// The least time between requests; a second unless given.
  final Duration? pause;
  DateTime? _last;

  static const sources = ['newspapers', 'books', 'wikitree'];

  void close() => _client.close();

  /// Pages of US newspapers in the Library of Congress's Chronicling
  /// America that have every one of [words], each with the passage around
  /// them. [from] and [to] are years; [state] is a US state.
  Future<List<Map<String, Object?>>> newspapers(
    String words, {
    int? from,
    int? to,
    String? state,
    int rows = 10,
  }) async {
    final search = await _json(
      Uri.https('www.loc.gov', '/collections/chronicling-america/', {
        'q': words,
        if (from != null || to != null)
          'dates': '${from ?? 1700}/${to ?? 1963}',
        if (state != null) 'fa': 'location_state:${state.toLowerCase()}',
        'fo': 'json',
        'c': '$rows',
      }),
    );
    final found = <Map<String, Object?>>[];
    for (final r in ((search as Map)['results'] as List? ?? const [])) {
      final result = r as Map<String, Object?>;
      String? snippet;
      if (result['word_coordinates_url'] case final String url) {
        // A page without its passage is still worth listing.
        try {
          final coords = await _json(Uri.parse(url));
          if (coords case final Map<String, Object?> m
              when m.values.firstOrNull is Map) {
            snippet = _untag(
              (m.values.first as Map)['relevant_snippet'] as String?,
            );
          }
        } on IOException {
          // No passage.
        } on FormatException {
          // No passage.
        }
      }
      found.add({
        ...newspaperPage(result, snippet: snippet),
        if (snippet != null) 'together': together(snippet, words),
      });
    }
    // The words need not be near each other on a page ("alice carew"
    // finds an Alice and a Carew in different columns), so the pages whose
    // passage has them together come first.
    final near = found.where((f) => f['together'] == true).toList();
    return [...near, ...found.where((f) => f['together'] != true)];
  }

  /// One page from a Chronicling America search [result], as a candidate.
  Map<String, Object?> newspaperPage(
    Map<String, Object?> result, {
    String? snippet,
  }) {
    // "Image 5 of The evening world (New York, N.Y.), April 28, 1891"
    final title = (result['title'] as String? ?? '').trim();
    final image = RegExp(r'^Image (\d+) of (.*)$').firstMatch(title);
    final city = _first(result['location_city']);
    final state = _first(result['location_state']);
    final link = (result['id'] as String? ?? result['url'] as String? ?? '')
        .replaceFirst('http://', 'https://');
    final imageUrl = _first(result['image_url'])
        ?.replaceFirst(RegExp(r'/full/pct:[\d.]+/'), '/full/pct:50/')
        .replaceFirst(RegExp(r'#.*$'), '');
    return {
      'item': {
        'title': image == null ? title : '${image[2]}, page ${image[1]}',
        'date': ?_isoDate(result['date'] as String?),
        if ([city, state].nonNulls.isNotEmpty)
          'place': [city, state].nonNulls.map(_capitalized).join(', '),
        'link': link,
        'found': _found('Chronicling America, Library of Congress'),
      },
      'snippet': ?snippet,
      'image': ?imageUrl,
    };
  }

  /// Books and other texts in the Internet Archive matching [query], which
  /// may use its fields: `title:(directory) AND title:(bronx)`.
  Future<List<Map<String, Object?>>> books(
    String query, {
    int? from,
    int? to,
    int rows = 10,
  }) async {
    final q = [
      '($query)',
      'mediatype:texts',
      if (from != null || to != null) 'year:[${from ?? 1500} TO ${to ?? 2100}]',
    ].join(' AND ');
    final search = await _json(
      Uri.https('archive.org', '/advancedsearch.php', {
        'q': q,
        'fl[]': [
          'identifier',
          'title',
          'volume',
          'year',
          'creator',
          'publisher',
        ],
        'rows': '$rows',
        'output': 'json',
      }),
    );
    final docs = ((search as Map)['response'] as Map?)?['docs'] as List?;
    return [for (final d in docs ?? const []) book(d as Map<String, Object?>)];
  }

  /// One text from an Internet Archive search, as a candidate.
  Map<String, Object?> book(Map<String, Object?> doc) {
    final id = doc['identifier'] as String;
    return {
      'item': {
        'title': [
          _first(doc['title']) ?? id,
          ?_first(doc['volume']),
        ].join(', '),
        if (doc['year'] != null) 'date': '${doc['year']}',
        'link': 'https://archive.org/details/$id',
        'found': _found('Internet Archive'),
      },
      'identifier': id,
      'creator': ?_first(doc['creator']),
      'publisher': ?_first(doc['publisher']),
    };
  }

  /// WikiTree profiles for [name], given and family name, born near [born].
  /// Leads to the records they cite, never sources.
  Future<List<Map<String, Object?>>> wikitree(
    String name, {
    int? born,
    int rows = 10,
  }) async {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length < 2) {
      throw const FormatException('Give a given name and a family name.');
    }
    final result = await _json(
      Uri.https('api.wikitree.com', '/api.php', {
        'appId': 'prosapia',
        'action': 'searchPerson',
        'FirstName': words.sublist(0, words.length - 1).join(' '),
        'LastName': words.last,
        if (born != null) 'BirthDate': '$born-01-01',
        // Asks for more than wanted, since the loose matches are dropped.
        'limit': '${rows * 5}',
        'fields':
            'Name,FirstName,MiddleName,LastNameAtBirth,LastNameCurrent,'
            'BirthDate,BirthLocation,DeathDate,DeathLocation',
      }),
    );
    final matches =
        ((result as List).firstOrNull as Map?)?['matches'] as List? ?? const [];
    // WikiTree's search is loose (Carew finds Carey and Crow): keep only
    // those with the family name given, at birth or later.
    final family = words.last.toLowerCase();
    return [
      for (final m in matches.cast<Map<String, Object?>>())
        if (m['Name'] case final String id
            when [
              m['LastNameAtBirth'],
              m['LastNameCurrent'],
            ].any((n) => n is String && n.toLowerCase() == family))
          profile(id, m),
    ].take(rows).toList();
  }

  /// One WikiTree profile, as a lead.
  Map<String, Object?> profile(String id, Map<String, Object?> m) {
    // `1863-00-00` is a year alone.
    String? date(Object? d) => d is String && !d.startsWith('0000')
        ? d.replaceAll(RegExp(r'(-00)+$'), '')
        : null;
    String? text(Object? s) => s is String && s.trim().isNotEmpty ? s : null;
    return {
      'wikiTreeId': id,
      'name': [
        m['FirstName'],
        m['MiddleName'],
        m['LastNameAtBirth'],
      ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
      if (m['LastNameCurrent'] != m['LastNameAtBirth'] &&
          text(m['LastNameCurrent']) != null)
        'laterName': m['LastNameCurrent'],
      'born': ?date(m['BirthDate']),
      'birthPlace': ?text(m['BirthLocation']),
      'died': ?date(m['DeathDate']),
      'deathPlace': ?text(m['DeathLocation']),
      'link': 'https://www.wikitree.com/wiki/$id',
    };
  }

  /// The passages of the text at [link] that have every one of [words]
  /// within [context] lines either side: a Chronicling America page or an
  /// Internet Archive text.
  Future<Map<String, Object?>> text(
    String link,
    List<String> words, {
    int context = 3,
  }) async {
    final uri = Uri.parse(link);
    final String text;
    if (uri.host.endsWith('loc.gov')) {
      final page = await _json(
        uri.replace(
          scheme: 'https',
          queryParameters: {...uri.queryParameters, 'fo': 'json'}..remove('q'),
        ),
      );
      final file =
          ((page as Map)['resource'] as Map?)?['fulltext_file'] as String?;
      if (file == null) throw FormatException('No text for $link.');
      final full = await _json(Uri.parse(file));
      text = ((full as Map).values.first as Map)['full_text'] as String;
    } else if (uri.host.endsWith('archive.org')) {
      final id = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
      if (id == null || uri.pathSegments.first != 'details') {
        throw FormatException('Give a link to a text: archive.org/details/…');
      }
      text = await _bookText(id);
    } else {
      throw FormatException(
        'Give a link to a Chronicling America page or an Internet Archive '
        'text, not $link.',
      );
    }
    final found = passages(text, words, context: context);
    return {
      'link': link,
      'words': words,
      'passages': found.take(20).toList(),
      if (found.length > 20) 'more': found.length - 20,
    };
  }

  Future<String> _bookText(String id) async {
    final cached = cacheDir == null
        ? null
        : File(p.join(cacheDir!, 'research', '$id.txt'));
    if (cached != null && cached.existsSync()) return cached.readAsStringSync();
    final meta = await _json(Uri.https('archive.org', '/metadata/$id'));
    final files = ((meta as Map)['files'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    final name = files
        .map((f) => f['name'] as String)
        .where((n) => n.endsWith('_djvu.txt'))
        .firstOrNull;
    if (name == null) throw FormatException('$id has no text to search.');
    final text = await _get(
      Uri.https('archive.org', '/download/$id/${Uri.encodeComponent(name)}'),
    );
    if (cached != null) {
      cached.parent.createSync(recursive: true);
      cached.writeAsStringSync(text);
    }
    return text;
  }

  Future<Object?> _json(Uri uri) async => jsonDecode(await _get(uri));

  static const _headers = {'User-Agent': 'prosapia-research'};

  Future<String> _get(Uri uri) async {
    final wait = pause ?? const Duration(seconds: 1);
    if (_last case final last?) {
      final left = wait - DateTime.now().difference(last);
      if (left > Duration.zero) await Future<void>.delayed(left);
    }
    _last = DateTime.now();
    http.Response response;
    try {
      response = await _client.get(uri, headers: _headers);
    } on http.ClientException {
      // A dropped connection is tried once more, after a longer pause.
      await Future<void>.delayed(wait * 3);
      _last = DateTime.now();
      try {
        response = await _client.get(uri, headers: _headers);
      } on http.ClientException catch (e) {
        throw HttpException('${uri.host}: ${e.message}', uri: uri);
      }
    }
    if (response.statusCode != 200) {
      throw HttpException(
        '${uri.host} answered ${response.statusCode}',
        uri: uri,
      );
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  String _found(String where) =>
      '${_today.day} ${TreeDate.months[_today.month - 1]} ${_today.year}, '
      '$where';

  static String? _first(Object? value) => switch (value) {
    final String s => s,
    final List<Object?> l when l.isNotEmpty => '${l.first}',
    _ => null,
  };

  static String _capitalized(String s) => s
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  /// `1891-04-28` as `28 April 1891`.
  static String? _isoDate(String? iso) {
    final m = RegExp(r'^(\d{4})-(\d\d)-(\d\d)$').firstMatch(iso ?? '');
    if (m == null) return iso;
    return '${int.parse(m[3]!)} ${TreeDate.months[int.parse(m[2]!) - 1]} '
        '${m[1]}';
  }

  static String? _untag(String? s) => s
      ?.replaceAll(RegExp(r'\[\[/?tag\]\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Whether every one of [words] (separated by spaces) is in [text] within a
/// few words of the others, each as the start of a word, ignoring case:
/// "Michael F. Carew" has `michael carew` together.
bool together(String text, String words, {int within = 4}) {
  final wanted = _wordsOf(words);
  if (wanted.isEmpty) return false;
  final tokens = _wordsOf(text);
  for (var i = 0; i < tokens.length; i++) {
    final window = tokens.sublist(
      i,
      (i + wanted.length + within).clamp(0, tokens.length),
    );
    if (wanted.every((w) => window.any((t) => t.startsWith(w)))) return true;
  }
  return false;
}

List<String> _wordsOf(String text) => [
  for (final m in RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(text))
    m[0]!.toLowerCase(),
];

/// The passages of [text] that have every one of [words], each a run of
/// lines: [context] lines either side of a line with the first word, kept
/// when the other words are in it too. Words match the start of a word,
/// ignoring case; runs that overlap are joined.
List<String> passages(String text, List<String> words, {int context = 3}) {
  if (words.isEmpty) return const [];
  final patterns = [
    for (final w in words)
      RegExp(
        '(?<![\\p{L}\\p{N}])${RegExp.escape(w)}',
        caseSensitive: false,
        unicode: true,
      ),
  ];
  final lines = text.split('\n');
  final runs = <(int, int)>[];
  for (var i = 0; i < lines.length; i++) {
    if (!patterns.first.hasMatch(lines[i])) continue;
    final start = (i - context).clamp(0, lines.length - 1);
    final end = (i + context).clamp(0, lines.length - 1);
    if (runs.isNotEmpty && start <= runs.last.$2 + 1) {
      runs.last = (runs.last.$1, end);
    } else {
      runs.add((start, end));
    }
  }
  return [
    for (final (start, end) in runs)
      if (lines.sublist(start, end + 1).join('\n') case final passage
          when patterns.every((p) => p.hasMatch(passage)))
        passage.trim(),
  ];
}
