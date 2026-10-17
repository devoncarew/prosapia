import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prosapia/src/assist.dart';
import 'package:prosapia/src/claude.dart';
import 'package:prosapia/src/index.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

http.Response reply(String text, {String stop = 'end_turn'}) => http.Response(
  jsonEncode({
    'content': [
      {'type': 'thinking', 'thinking': ''},
      {'type': 'text', 'text': text},
    ],
    'stop_reason': stop,
    'usage': {'input_tokens': 1000000, 'output_tokens': 100000},
  }),
  200,
);

void main() {
  setUp(() => Claude.backoff = (_, _) => Duration.zero);

  group('Claude', () {
    test('sends the request and reads the text and its cost', () async {
      late Map<String, Object?> sent;
      late Map<String, String> headers;
      final claude = Claude(
        'key',
        client: MockClient((request) async {
          sent = (jsonDecode(request.body) as Map).cast<String, Object?>();
          headers = request.headers;
          return reply('Hello.');
        }),
      );
      final r = await claude.write(Model.fast, system: 'S', user: 'U');
      expect(r.text, 'Hello.');
      expect(r.cost, closeTo(0.10 + 0.05, 1e-9));
      expect(sent['model'], 'claude-haiku-5-5');
      expect(sent['system'], 'S');
      expect(sent.containsKey('fallbacks'), isFalse);
      expect(headers['x-api-key'], 'key');
      expect(headers['anthropic-version'], '2023-06-01');
    });

    test('the writing model falls back if it declines', () async {
      late http.Request seen;
      final claude = Claude(
        'key',
        client: MockClient((request) async {
          seen = request;
          return reply('x');
        }),
      );
      await claude.write(Model.writer, system: '', user: '');
      expect((jsonDecode(seen.body) as Map)['fallbacks'], 'default');
      expect(seen.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
    });

    test('retries overloads, then gives up on other errors', () async {
      var calls = 0;
      final claude = Claude(
        'key',
        client: MockClient((request) async {
          calls++;
          return calls == 1 ? http.Response('{}', 529) : reply('ok');
        }),
      );
      expect((await claude.write(Model.fast, system: '', user: '')).text, 'ok');
      expect(calls, 2);

      final failing = Claude(
        'key',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'bad key'},
            }),
            401,
          ),
        ),
      );
      expect(
        failing.write(Model.fast, system: '', user: ''),
        throwsA(
          isA<ClaudeException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.message, 'message', 'bad key'),
        ),
      );
    });

    test('a refusal is reported', () async {
      final claude = Claude(
        'key',
        client: MockClient((_) async => reply('', stop: 'refusal')),
      );
      expect(
        (await claude.write(Model.fast, system: '', user: '')).refused,
        isTrue,
      );
    });
  });

  group('Assistant', () {
    final tree = Tree('test');
    for (final (dir, source) in [
      (
        'hughes-thomas-3f8d1a',
        'Name: Thomas Hughes\nBorn: 1852\nChildren: @hughes-margaret-7k2m9x\n',
      ),
      (
        'hughes-margaret-7k2m9x',
        'Name: Margaret Hughes\nBorn: 1887\n\nShe taught school.\n',
      ),
    ]) {
      final p = Person.fromSource('p-${dir.split('-').last}', dir, source);
      tree.people[p.id] = p;
    }
    final index = Index.build(tree);
    final guide = WritingGuide(biographies: 'BIO GUIDE', summaries: 'SUM');

    Future<Map<String, Object?>> ask(
      Future<Reply> Function(Assistant, Person) call, {
      String answer = 'Text.',
    }) async {
      late Map<String, Object?> sent;
      final assistant = Assistant(
        Claude(
          'key',
          client: MockClient((r) async {
            sent = (jsonDecode(r.body) as Map).cast<String, Object?>();
            return reply(answer);
          }),
        ),
        guide,
      );
      final result = await call(assistant, tree.people['p-7k2m9x']!);
      return {...sent, 'result': result.text};
    }

    String userOf(Map<String, Object?> sent) =>
        ((sent['messages'] as List).single as Map)['content'] as String;

    test(
      'a draft sees the page, the guide, the relatives and the notes',
      () async {
        final sent = await ask(
          (a, p) => a.draft(
            person: p,
            source: p.source,
            tree: tree,
            index: index,
            instruction: 'Add her years in Hartford.',
            notes: 'Taught in Hartford, 1910 to 1915.',
          ),
        );
        expect(sent['model'], 'claude-opus-5-5');
        expect(sent['system'], contains('BIO GUIDE'));
        final user = userOf(sent);
        expect(user, contains('Name: Margaret Hughes'));
        expect(
          user,
          contains(
            '@hughes-thomas-3f8d1a: Thomas Hughes (born 1852), '
            "Margaret Hughes's parent",
          ),
        );
        expect(user, contains('Keep its wording'));
        expect(user, contains('The editor asks: Add her years in Hartford.'));
        expect(user, contains('<notes>'));
        expect(user, contains('Taught in Hartford, 1910 to 1915.'));
      },
    );

    test('an empty story is drafted, with the suggested request', () async {
      final sent = await ask(
        (a, p) => a.draft(
          person: p,
          source: 'Name: Margaret Hughes\nBorn: 1887\n',
          tree: tree,
          index: index,
        ),
      );
      final user = userOf(sent);
      expect(user, contains('The story below the facts is empty'));
      expect(user, contains('The editor asks: ${Assistant.firstDraft}'));
      expect(user, isNot(contains('<notes>')));
      // A first draft draws on the rest of the tree, and says from where.
      expect(user, contains('<elsewhere>'));
      expect(
        user,
        contains("Thomas Hughes's facts (Margaret Hughes's parent)"),
      );
      expect(user, contains(Assistant.drawnFromMarker));
    });

    test('a revision is not given the rest of the tree', () async {
      final sent = await ask(
        (a, p) =>
            a.draft(person: p, source: p.source, tree: tree, index: index),
      );
      expect(userOf(sent), isNot(contains('<elsewhere>')));
    });

    test('the sources of a first draft are split from its story', () {
      final split = Assistant.splitDrawnFrom(
        'She taught.\n\n${Assistant.drawnFromMarker}\n'
        "- Thomas Hughes's facts: his birth year\n\n",
      );
      expect(split.story, 'She taught.');
      expect(split.drawnFrom, ["Thomas Hughes's facts: his birth year"]);
      expect(Assistant.splitDrawnFrom('Text.').drawnFrom, isEmpty);
    });

    test('research ideas suggest records, not facts', () async {
      final sent = await ask(
        (a, p) => a.researchIdeas(person: p, tree: tree, index: index),
      );
      expect(sent['system'], contains('FamilySearch'));
      final user = userOf(sent);
      expect(user, contains('Name: Margaret Hughes'));
      expect(user, contains('not what will be found'));
      expect(user, contains('living person'));
    });

    test('a code fence around the reply is removed', () async {
      final sent = await ask(
        (a, p) =>
            a.draft(person: p, source: p.source, tree: tree, index: index),
        answer: '```markdown\nShe was born in 1887.\n```',
      );
      expect(sent['result'], 'She was born in 1887.');
    });

    test('the guide is read from docs/writing.md', () {
      final guide = WritingGuide.load();
      expect(guide.biographies, contains('Only what the tree holds'));
      expect(guide.summaries, contains('under 70 characters'));
    });
  });
}
