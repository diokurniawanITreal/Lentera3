import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../core/app_config.dart';

enum AiFailure {
  notConfigured,
  offline,
  timeout,
  rateLimited,
  server,
  empty,
  cancelled,
}

class AiException implements Exception {
  const AiException(this.failure);
  final AiFailure failure;
}

abstract class AiService {
  Future<String> ask(String question);

  /// Membatalkan permintaan yang sedang berjalan (mis. saat pindah mode).
  void cancel();
}

/// Klien HTTPS ke backend proxy. API key Gemini TIDAK ada di aplikasi.
///
/// Kontrak:
///   POST {endpoint}  body: {"question": "...", "language": "id"}
///   200  -> {"answer": "..."}
///   429  -> batas penggunaan | 5xx -> kesalahan server
class GeminiProxyService implements AiService {
  GeminiProxyService({
    String? endpoint,
    String? clientToken,
    http.Client Function()? clientFactory,
    Duration? timeout,
  })  : _endpoint = endpoint ?? AppConfig.aiEndpoint,
        _token = clientToken ?? AppConfig.clientToken,
        _factory = clientFactory ?? http.Client.new,
        _timeout = timeout ?? AppConfig.aiTimeout;

  final String _endpoint;
  final String _token;
  final http.Client Function() _factory;
  final Duration _timeout;

  http.Client? _active;
  bool _cancelled = false;

  @override
  Future<String> ask(String question) async {
    final uri = Uri.tryParse(_endpoint);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const AiException(AiFailure.notConfigured);
    }
    _cancelled = false;
    final client = _factory();
    _active = client;
    try {
      final res = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              if (_token.isNotEmpty) 'X-Lentera-Token': _token,
            },
            body: jsonEncode({'question': question, 'language': 'id'}),
          )
          .timeout(_timeout);
      if (_cancelled) throw const AiException(AiFailure.cancelled);
      if (res.statusCode == 429) {
        throw const AiException(AiFailure.rateLimited);
      }
      if (res.statusCode != 200) {
        throw const AiException(AiFailure.server);
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final answer = json is Map<String, dynamic> ? json['answer'] : null;
      if (answer is! String || answer.trim().isEmpty) {
        throw const AiException(AiFailure.empty);
      }
      return answer;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw const AiException(AiFailure.timeout);
    } on SocketException {
      throw AiException(_cancelled ? AiFailure.cancelled : AiFailure.offline);
    } on http.ClientException {
      throw AiException(_cancelled ? AiFailure.cancelled : AiFailure.offline);
    } on FormatException {
      throw const AiException(AiFailure.server);
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  @override
  void cancel() {
    _cancelled = true;
    _active?.close();
  }
}
