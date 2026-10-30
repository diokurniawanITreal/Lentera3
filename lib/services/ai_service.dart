import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/app_log.dart';

// ──────────────────────────────────────────────────────────────────────────────
//  ENUM & EXCEPTION
// ──────────────────────────────────────────────────────────────────────────────

/// Jenis kegagalan layanan AI.
enum AiFailure {
  /// Belum ada backend URL atau API Key yang dikonfigurasi.
  notConfigured,

  /// Perangkat offline atau jaringan tidak dapat dijangkau.
  offline,

  /// Permintaan ke server AI melebihi batas waktu (timeout).
  timeout,

  /// Batas kuota request tercapai (HTTP 429).
  rateLimited,

  /// Kesalahan pada sisi server / API.
  server,

  /// AI tidak memberikan teks jawaban (respons kosong).
  empty,

  /// Permintaan sengaja dibatalkan (misal: pengguna menekan tombol interupsi
  /// atau berpindah mode saat request sedang berlangsung).
  cancelled,
}

class AiException implements Exception {
  const AiException(this.failure, [this.message]);
  final AiFailure failure;
  final String? message;

  @override
  String toString() =>
      'AiException(${failure.name}${message != null ? ': $message' : ''})';
}

// ──────────────────────────────────────────────────────────────────────────────
//  ABSTRACT INTERFACE
// ──────────────────────────────────────────────────────────────────────────────

abstract class AiService {
  /// Mengirim pertanyaan ke AI dan mengembalikan teks jawaban.
  Future<String> ask(String question);

  /// Membatalkan permintaan aktif (mis. saat pindah mode atau interupsi suara).
  void cancel();

  /// Status apakah ada permintaan yang sedang berlangsung.
  bool get isLoading => false;
}

// ──────────────────────────────────────────────────────────────────────────────
//  IMPLEMENTATION: Gemini (Dual Mode: Proxy Backend / Direct API)
// ──────────────────────────────────────────────────────────────────────────────

/// Layanan AI Gemini yang fleksibel dan aman:
/// 1. **Mode Proxy**: Menggunakan endpoint Cloudflare Worker yang menyembunyikan
///    API key (cocok untuk produksi).
/// 2. **Mode Direct Gemini**: Menggunakan Google Generative AI API secara langsung
///    dengan API Key (cocok untuk pengembangan/testing tanpa perlu deploy backend).
class GeminiProxyService implements AiService {
  GeminiProxyService({
    String? endpoint,
    String? clientToken,
    String? apiKey,
    String? model,
    http.Client Function()? clientFactory,
    Duration? timeout,
  }) : _endpoint = endpoint ?? AppConfig.aiEndpoint,
       _token = clientToken ?? AppConfig.clientToken,
       _apiKey = apiKey ?? AppConfig.geminiApiKey,
       _model = model ?? AppConfig.geminiModel,
       _factory = clientFactory ?? http.Client.new,
       _timeout = timeout ?? AppConfig.aiTimeout;

  final String _endpoint;
  final String _token;
  final String _apiKey;
  final String _model;
  final http.Client Function() _factory;
  final Duration _timeout;

  http.Client? _active;
  bool _cancelled = false;
  bool _isLoading = false;

  /// Memeriksa apakah mode proxy aktif dan valid.
  bool get _isProxyMode {
    final uri = Uri.tryParse(_endpoint);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// Memeriksa apakah mode direct Google Gemini API aktif.
  bool get _isDirectGeminiMode => _apiKey.trim().isNotEmpty;

  /// Memeriksa apakah salah satu konfigurasi AI tersedia.
  bool get isConfigured => _isProxyMode || _isDirectGeminiMode;

  @override
  bool get isLoading => _isLoading;

  @override
  Future<String> ask(String question) async {
    // 1. Validasi input — cegah pengiriman string kosong ke server
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      throw const AiException(
        AiFailure.empty,
        'Pertanyaan tidak boleh kosong.',
      );
    }

    // 2. Validasi konfigurasi
    if (!isConfigured) {
      AppLog.d('AI', 'Layanan AI belum dikonfigurasi (URL / API Key kosong).');
      throw const AiException(
        AiFailure.notConfigured,
        'Layanan AI belum dikonfigurasi.',
      );
    }

    // 3. Pencegahan race-condition: tutup request lama sebelum memulai yang baru
    _active?.close();
    _active = null;
    _cancelled = false;
    _isLoading = true;

    final client = _factory();
    _active = client;

    try {
      if (_cancelled) throw const AiException(AiFailure.cancelled);

      // Jalankan sesuai mode yang dikonfigurasi
      final String answer;
      if (_isProxyMode) {
        answer = await _askProxy(client, trimmed);
      } else {
        answer = await _askDirectGemini(client, trimmed);
      }

      if (_cancelled) throw const AiException(AiFailure.cancelled);
      return answer;
    } on AiException {
      rethrow;
    } on TimeoutException {
      AppLog.d('AI', 'Permintaan timeout setelah ${_timeout.inSeconds} detik');
      throw const AiException(AiFailure.timeout, 'Waktu tunggu AI habis.');
    } on SocketException {
      AppLog.d(
        'AI',
        _cancelled ? 'Koneksi socket dibatalkan' : 'Offline (socket)',
      );
      throw AiException(
        _cancelled ? AiFailure.cancelled : AiFailure.offline,
        'Koneksi internet bermasalah.',
      );
    } on http.ClientException {
      AppLog.d(
        'AI',
        _cancelled ? 'Client HTTP dibatalkan' : 'Client HTTP error',
      );
      throw AiException(
        _cancelled ? AiFailure.cancelled : AiFailure.offline,
        'Gagal menghubungi server.',
      );
    } on FormatException catch (e) {
      AppLog.d('AI', 'Format JSON rusak: $e');
      throw const AiException(AiFailure.server, 'Format data tidak valid.');
    } catch (e) {
      AppLog.d('AI', 'Kesalahan tidak terduga: ${e.runtimeType}');
      throw const AiException(AiFailure.server, 'Terjadi kesalahan sistem.');
    } finally {
      client.close();
      if (identical(_active, client)) {
        _active = null;
        _isLoading = false;
      }
    }
  }

  /// Request via Cloudflare Worker Proxy
  Future<String> _askProxy(http.Client client, String question) async {
    final uri = Uri.parse(_endpoint);
    AppLog.d('AI', 'Mengirim pertanyaan via Proxy (${uri.host})...');

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

    if (res.statusCode == 401 || res.statusCode == 403) {
      AppLog.d('AI', 'Token proxy tidak valid: HTTP ${res.statusCode}');
      throw const AiException(
        AiFailure.notConfigured,
        'Token autentikasi AI salah atau kedaluwarsa.',
      );
    }

    if (res.statusCode == 429) {
      AppLog.d('AI', 'Rate limited di proxy: HTTP 429');
      throw const AiException(AiFailure.rateLimited);
    }

    if (res.statusCode != 200) {
      AppLog.d('AI', 'Proxy error: HTTP ${res.statusCode}');
      throw const AiException(AiFailure.server);
    }

    final json = jsonDecode(utf8.decode(res.bodyBytes));
    final answer = json is Map<String, dynamic> ? json['answer'] : null;

    if (answer is! String || answer.trim().isEmpty) {
      AppLog.d('AI', 'Jawaban kosong dari proxy.');
      throw const AiException(AiFailure.empty);
    }

    return answer.trim();
  }

  /// Request langsung ke Google Gemini REST API (Google AI Studio)
  Future<String> _askDirectGemini(http.Client client, String question) async {
    final uri = Uri.parse(
      '${AppConfig.geminiBaseUrl}/$_model:generateContent',
    );
    AppLog.d('AI', 'Mengirim pertanyaan direct ke Gemini ($_model)...');

    final payload = {
      'systemInstruction': {
        'parts': [
          {'text': AppConfig.aiSystemPrompt},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': question},
          ],
        },
      ],
      'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 1024},
    };

    final res = await client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'x-goog-api-key': _apiKey,
          },
          body: jsonEncode(payload),
        )
        .timeout(_timeout);

    if (_cancelled) throw const AiException(AiFailure.cancelled);

    if (res.statusCode == 401 || res.statusCode == 403) {
      AppLog.d('AI', 'API Key Gemini ditolak: HTTP ${res.statusCode}');
      throw const AiException(
        AiFailure.notConfigured,
        'Kunci API Gemini tidak valid atau tidak diizinkan.',
      );
    }

    if (res.statusCode == 429) {
      AppLog.d('AI', 'Gemini Quota Exceeded: HTTP 429');
      throw const AiException(AiFailure.rateLimited);
    }

    if (res.statusCode != 200) {
      AppLog.d('AI', 'Gemini HTTP error: ${res.statusCode}');
      throw const AiException(AiFailure.server);
    }

    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is! Map<String, dynamic>) {
      throw const AiException(
        AiFailure.server,
        'Format respons bukan JSON objek.',
      );
    }

    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      AppLog.d('AI', 'Tidak ada kandidat jawaban dalam respons Gemini.');
      throw const AiException(AiFailure.empty);
    }

    final firstCandidate = candidates.first;
    if (firstCandidate is! Map<String, dynamic>) {
      throw const AiException(AiFailure.empty);
    }

    final content = firstCandidate['content'];
    final parts = content is Map<String, dynamic> ? content['parts'] : null;
    if (parts is! List || parts.isEmpty) {
      throw const AiException(AiFailure.empty);
    }

    final textParts = <String>[];
    for (final p in parts) {
      if (p is Map<String, dynamic> && p['text'] is String) {
        textParts.add(p['text'] as String);
      }
    }

    final answer = textParts.join('').trim();
    if (answer.isEmpty) {
      AppLog.d('AI', 'Teks jawaban Gemini kosong setelah diekstrak.');
      throw const AiException(AiFailure.empty);
    }

    return answer;
  }

  @override
  void cancel() {
    _cancelled = true;
    _isLoading = false;
    final client = _active;
    _active = null;
    client?.close();
    AppLog.d('AI', 'Request AI dibatalkan.');
  }
}
