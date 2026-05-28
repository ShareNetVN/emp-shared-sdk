import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/sso_config.dart';
import '../exceptions/sso_exceptions.dart';
import '../models/sso_user.dart';
import '../models/token_response.dart';

/// HTTP client cho Authentication Service. Stateless — không giữ token.
/// Việc inject `Authorization` header thuộc trách nhiệm của caller
/// (`EmpSso` lấy access token từ storage).
class SsoApiClient {
  SsoApiClient({required this.config, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final SsoConfig config;
  final http.Client _http;

  Future<TokenResponse> exchangeOneTimeCode({
    required String code,
    required String state,
    required String appId,
    String? deviceId,
  }) async {
    final body = {
      'code': code,
      'state': state,
      'appId': appId,
      if (deviceId != null) 'deviceId': deviceId,
    };
    final res = await _post(config.exchangeUrl, body: body);
    return TokenResponse.fromJson(_decodeJson(res));
  }

  Future<TokenResponse> refresh({required String refreshToken}) async {
    final res = await _post(config.refreshUrl, body: {'refreshToken': refreshToken});
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const SsoSessionExpiredException();
    }
    return TokenResponse.fromJson(_decodeJson(res));
  }

  Future<void> logout({required String refreshToken, String? accessToken}) async {
    await _post(
      config.logoutUrl,
      body: {'refreshToken': refreshToken},
      accessToken: accessToken,
      allowNoBody: true,
    );
  }

  Future<SsoUser> getMe({required String accessToken}) async {
    final res = await _get(config.meUrl, accessToken: accessToken);
    return SsoUser.fromJson(_decodeJson(res));
  }

  void close() => _http.close();

  // ─── internal ────────────────────────────────────────────────────────────

  Future<http.Response> _post(
    String url, {
    required Map<String, dynamic> body,
    String? accessToken,
    bool allowNoBody = false,
  }) async {
    try {
      final res = await _http
          .post(
            Uri.parse(url),
            headers: _headers(accessToken: accessToken),
            body: jsonEncode(body),
          )
          .timeout(config.requestTimeout);
      _ensureSuccess(res, allowNoBody: allowNoBody);
      return res;
    } on TimeoutException catch (e) {
      throw SsoNetworkException('Request timeout: $url', cause: e);
    } on SocketException catch (e) {
      throw SsoNetworkException('Network error: ${e.message}', cause: e);
    } on http.ClientException catch (e) {
      throw SsoNetworkException('HTTP client error: ${e.message}', cause: e);
    }
  }

  Future<http.Response> _get(String url, {String? accessToken}) async {
    try {
      final res = await _http
          .get(Uri.parse(url), headers: _headers(accessToken: accessToken))
          .timeout(config.requestTimeout);
      _ensureSuccess(res);
      return res;
    } on TimeoutException catch (e) {
      throw SsoNetworkException('Request timeout: $url', cause: e);
    } on SocketException catch (e) {
      throw SsoNetworkException('Network error: ${e.message}', cause: e);
    }
  }

  Map<String, String> _headers({String? accessToken}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-App-Id': config.appId,
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }

  void _ensureSuccess(http.Response res, {bool allowNoBody = false}) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String? errorCode;
    String message = 'HTTP ${res.statusCode}';
    if (!allowNoBody && res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          errorCode = decoded['errorCode'] as String? ?? decoded['code'] as String?;
          message = (decoded['message'] as String?) ?? message;
        }
      } catch (_) {/* ignore — fall through with default message */}
    }
    throw SsoAuthException(message, statusCode: res.statusCode, errorCode: errorCode);
  }

  Map<String, dynamic> _decodeJson(http.Response res) {
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SsoAuthException('Response body is not a JSON object');
    }
    return decoded;
  }
}
