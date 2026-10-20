import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lentera3/services/ai_service.dart';

void main() {
  group('GeminiProxyService - Validasi & Konfigurasi', () {
    test('pertanyaan kosong / spasi melempar AiFailure.empty', () async {
      final service = GeminiProxyService(
        endpoint: 'https://example.com/ai',
      );
      expect(
        () => service.ask('   '),
        throwsA(isA<AiException>().having(
          (e) => e.failure,
          'failure',
          AiFailure.empty,
        )),
      );
    });

    test('layanan belum dikonfigurasi melempar AiFailure.notConfigured', () async {
      final service = GeminiProxyService(
        endpoint: '',
        apiKey: '',
      );
      expect(
        () => service.ask('Halo'),
        throwsA(isA<AiException>().having(
          (e) => e.failure,
          'failure',
          AiFailure.notConfigured,
        )),
      );
    });
  });

  group('GeminiProxyService - Mode Proxy Backend', () {
    test('berhasil memproses respons dari proxy', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'https://api.example.com/ai');
        expect(request.headers['X-Lentera-Token'], 'my-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['question'], 'Siapa presiden Indonesia?');
        expect(body['language'], 'id');

        return http.Response(
          jsonEncode({'answer': 'Presiden Indonesia adalah Joko Widodo.'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = GeminiProxyService(
        endpoint: 'https://api.example.com/ai',
        clientToken: 'my-token',
        clientFactory: () => mockClient,
      );

      final result = await service.ask('Siapa presiden Indonesia?');
      expect(result, 'Presiden Indonesia adalah Joko Widodo.');
    });

    test('HTTP 401 token ditolak melempar AiFailure.notConfigured', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
      });

      final service = GeminiProxyService(
        endpoint: 'https://api.example.com/ai',
        clientFactory: () => mockClient,
      );

      expect(
        () => service.ask('Halo'),
        throwsA(isA<AiException>().having(
          (e) => e.failure,
          'failure',
          AiFailure.notConfigured,
        )),
      );
    });

    test('HTTP 429 rate limited melempar AiFailure.rateLimited', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'rate_limited'}), 429);
      });

      final service = GeminiProxyService(
        endpoint: 'https://api.example.com/ai',
        clientFactory: () => mockClient,
      );

      expect(
        () => service.ask('Halo'),
        throwsA(isA<AiException>().having(
          (e) => e.failure,
          'failure',
          AiFailure.rateLimited,
        )),
      );
    });

    test('respons jawaban kosong melempar AiFailure.empty', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'answer': '   '}), 200);
      });

      final service = GeminiProxyService(
        endpoint: 'https://api.example.com/ai',
        clientFactory: () => mockClient,
      );

      expect(
        () => service.ask('Halo'),
        throwsA(isA<AiException>().having(
          (e) => e.failure,
          'failure',
          AiFailure.empty,
        )),
      );
    });
  });

  group('GeminiProxyService - Mode Direct Gemini API', () {
    test('berhasil memproses respons langsung dari Google Gemini API', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['key'], 'test-api-key');
        expect(request.url.path, contains('gemini-1.5-flash:generateContent'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['systemInstruction'], isNotNull);
        expect(body['contents'], isNotEmpty);

        final geminiResponse = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Ini adalah jawaban langsung dari Gemini.'}
                ]
              }
            }
          ]
        };

        return http.Response(
          jsonEncode(geminiResponse),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = GeminiProxyService(
        endpoint: '', // non-proxy
        apiKey: 'test-api-key',
        model: 'gemini-1.5-flash',
        clientFactory: () => mockClient,
      );

      final result = await service.ask('Apa itu kecerdasan buatan?');
      expect(result, 'Ini adalah jawaban langsung dari Gemini.');
    });

    test('direct Gemini API Key salah melempar AiFailure.notConfigured', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'error': {'code': 401}}), 401);
      });

      final service = GeminiProxyService(
        endpoint: '',
        apiKey: 'invalid-key',
        clientFactory: () => mockClient,
      );

      expect(
        () => service.ask('Halo'),
        throwsA(isA<AiException>().having(
          (e) => e.failure,
          'failure',
          AiFailure.notConfigured,
        )),
      );
    });
  });

  group('GeminiProxyService - Cancel & Jaringan', () {
    test('cancel() membatalkan request aktif', () async {
      final mockClient = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response(jsonEncode({'answer': 'terlambat'}), 200);
      });

      final service = GeminiProxyService(
        endpoint: 'https://api.example.com/ai',
        clientFactory: () => mockClient,
      );

      final future = service.ask('Pertanyaan');
      service.cancel();

      expect(
        () => future,
        throwsA(isA<AiException>().having(
          (e) => e.failure,
          'failure',
          AiFailure.cancelled,
        )),
      );
      expect(service.isLoading, isFalse);
    });

    test('SocketException melempar AiFailure.offline', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('No Internet');
      });

      final service = GeminiProxyService(
        endpoint: 'https://api.example.com/ai',
        clientFactory: () => mockClient,
      );

      expect(
        () => service.ask('Halo'),
        throwsA(isA<AiException>().having(
          (e) => e.failure,
          'failure',
          AiFailure.offline,
        )),
      );
    });
  });
}

