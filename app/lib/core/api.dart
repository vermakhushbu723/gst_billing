import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Thin JSON client for the GST Billing backend.
class Api {
  Api._();
  static final Api instance = Api._();

  /// Set with --dart-define=API_URL=https://example.com/api when building.
  static String get baseUrl {
    const env = String.fromEnvironment('API_URL');
    if (env.isNotEmpty) return env;
    if (kIsWeb) {
      // `flutter run -d chrome` uses a random port, so point debug builds at the local API.
      if (kDebugMode && (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1')) return 'http://localhost:4100/api';
      return '${Uri.base.origin}/api'; // web build served by the backend / same domain
    }
    return 'http://10.0.2.2:4100/api'; // Android emulator -> host machine
  }

  String? token;
  VoidCallback? onUnauthorized;

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? {});
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body ?? {});
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    return q.isEmpty ? uri : uri.replace(queryParameters: q);
  }

  Map<String, String> get _authHeader => token == null ? {} : {'Authorization': 'Bearer $token'};

  Future<dynamic> _send(String method, String path, {Map<String, dynamic>? query, Object? body}) async {
    final req = http.Request(method, _uri(path, query));
    req.headers.addAll({'Accept': 'application/json', ..._authHeader});
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    late http.Response res;
    try {
      res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 40)));
    } catch (_) {
      throw ApiException(0, 'Cannot reach server. Check your internet connection.');
    }
    return _handle(res, path);
  }

  dynamic _handle(http.Response res, String path) {
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 400) {
      if (res.statusCode == 401 && token != null && !path.startsWith('/auth/login')) onUnauthorized?.call();
      final msg = data is Map && data['message'] != null ? '${data['message']}' : 'Server error (${res.statusCode})';
      throw ApiException(res.statusCode, msg);
    }
    return data;
  }

  /// Uploads a rendered invoice PDF and returns its public link (for WhatsApp).
  Future<String> uploadInvoicePdf(String invoiceId, Uint8List bytes, String fileName) async {
    final req = http.MultipartRequest('POST', _uri('/invoices/$invoiceId/share-pdf'));
    req.headers.addAll(_authHeader);
    req.files.add(http.MultipartFile.fromBytes('pdf', bytes, filename: fileName));
    late http.Response res;
    try {
      res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 60)));
    } catch (_) {
      throw ApiException(0, 'Cannot reach server. Check your internet connection.');
    }
    final data = _handle(res, '/share-pdf');
    return '${data['url']}';
  }
}
