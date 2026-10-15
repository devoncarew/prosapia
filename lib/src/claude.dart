import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// A Claude model, with what it costs, for recording each call's cost.
class Model {
  const Model(this.id, this.name, {required this.input, required this.output});

  final String id;

  /// The name shown to readers: "Claude Haiku".
  final String name;

  /// US dollars per million tokens.
  final double input, output;

  /// Writing biographies and paragraphs.
  static const writer = Model(
    'claude-opus-5-5',
    'Claude Opus',
    input: 4,
    output: 20,
  );

  /// Change summaries and tidying.
  static const fast = Model(
    'claude-haiku-5-5',
    'Claude Haiku',
    input: 0.10,
    output: 0.50,
  );

  static const all = [writer, fast];

  static Model? byId(String? id) => all.where((m) => m.id == id).firstOrNull;
}

/// What a call returned, and what it cost.
class Reply {
  Reply(this.text, this.model, {required this.cost, required this.refused});

  final String text;
  final Model model;

  /// US dollars.
  final double cost;

  /// The model declined the request.
  final bool refused;
}

class ClaudeException implements Exception {
  ClaudeException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => 'ClaudeException($status): $message';
}

/// Calls the Claude Messages API over HTTP. Dart has no official Anthropic
/// SDK, so this is the request and response shape from the API reference.
class Claude {
  Claude(
    this.apiKey, {
    http.Client? client,
    this.maxRetries = 2,
    String baseUrl = 'https://api.anthropic.com',
  }) : _http = client ?? http.Client(),
       _endpoint = Uri.parse('$baseUrl/v1/messages');

  final String apiKey;
  final int maxRetries;
  final http.Client _http;
  final Uri _endpoint;

  /// Sends one request: [system] instructions and a single [user] message,
  /// after any [images], which are JPEGs. Retries rate limits, overloads
  /// and server errors.
  Future<Reply> write(
    Model model, {
    required String system,
    required String user,
    List<List<int>> images = const [],
    String effort = 'medium',
    int maxTokens = 16000,
  }) async {
    final body = jsonEncode({
      'model': model.id,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {
          'role': 'user',
          'content': images.isEmpty
              ? user
              : [
                  for (final jpeg in images)
                    {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': 'image/jpeg',
                        'data': base64Encode(jpeg),
                      },
                    },
                  {'type': 'text', 'text': user},
                ],
        },
      ],
      'output_config': {'effort': effort},
      // If the writing model declines, the API retries on a suitable one.
      if (model == Model.writer) 'fallbacks': 'default',
    });
    final headers = {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      if (model == Model.writer)
        'anthropic-beta': 'server-side-fallback-2026-07-01',
    };

    for (var attempt = 0; ; attempt++) {
      final http.Response response;
      try {
        response = await _http
            .post(_endpoint, headers: headers, body: body)
            .timeout(const Duration(minutes: 3));
      } on Exception catch (e) {
        if (attempt < maxRetries) {
          await _wait(attempt, null);
          continue;
        }
        throw ClaudeException('Could not reach Claude: $e');
      }
      final status = response.statusCode;
      if (status == 200) return _reply(model, response.body);
      final retryable = status == 408 || status == 429 || status >= 500;
      if (retryable && attempt < maxRetries) {
        await _wait(attempt, response.headers['retry-after']);
        continue;
      }
      throw ClaudeException(_errorMessage(response.body), status: status);
    }
  }

  static Reply _reply(Model model, String body) {
    final json = jsonDecode(body) as Map<String, Object?>;
    final text = [
      for (final block
          in (json['content'] as List? ?? const [])
              .cast<Map<String, Object?>>())
        if (block['type'] == 'text') block['text'] as String,
    ].join();
    final usage = (json['usage'] as Map?)?.cast<String, Object?>() ?? const {};
    int tokens(String key) => (usage[key] as num?)?.toInt() ?? 0;
    // Cache writes cost a quarter more than input; cache reads a tenth.
    final input =
        tokens('input_tokens') +
        tokens('cache_creation_input_tokens') * 1.25 +
        tokens('cache_read_input_tokens') * 0.1;
    final cost =
        (input * model.input + tokens('output_tokens') * model.output) / 1e6;
    return Reply(
      text.trim(),
      model,
      cost: cost,
      refused: json['stop_reason'] == 'refusal',
    );
  }

  static String _errorMessage(String body) {
    try {
      final error = (jsonDecode(body) as Map)['error'] as Map?;
      return error?['message'] as String? ?? body;
    } on FormatException {
      return body;
    }
  }

  static final _random = Random();

  /// How long to wait before retrying; zero in tests.
  static Duration Function(int attempt, String? retryAfter) backoff = _backoff;

  static Future<void> _wait(int attempt, String? retryAfter) =>
      Future.delayed(backoff(attempt, retryAfter));

  static Duration _backoff(int attempt, String? retryAfter) {
    final seconds = int.tryParse(retryAfter ?? '');
    return seconds != null
        ? Duration(seconds: seconds)
        : Duration(
            milliseconds: 500 * pow(2, attempt).toInt() + _random.nextInt(250),
          );
  }

  void close() => _http.close();
}
