import 'dart:async';
import 'dart:developer' as developer;

import 'api/sso_api_client.dart';
import 'config/sso_config.dart';
import 'exceptions/sso_exceptions.dart';
import 'models/deep_link_params.dart';
import 'models/sso_auth_event.dart';
import 'models/sso_user.dart';
import 'models/token_response.dart';
import 'storage/secure_token_storage.dart';

/// Entry point chính của EMP Shared SSO SDK cho Flutter.
///
/// Singleton (theo spec — mỗi app con chỉ có 1 SSO session active).
/// Mọi method đều static để app con dùng dễ:
///
/// ```dart
/// await EmpSso.initialize(SsoConfig(...));
/// final user = await EmpSso.handleDeepLink(uri);
/// ```
class EmpSso {
  EmpSso._();

  static SsoConfig? _config;
  static SsoApiClient? _api;
  static SecureTokenStorage? _storage;
  static final StreamController<SsoAuthEvent> _events =
      StreamController<SsoAuthEvent>.broadcast();

  /// In-flight refresh để tránh nhiều caller cùng refresh song song.
  static Future<TokenResponse>? _pendingRefresh;

  /// Stream phát các sự kiện auth (authenticated / refreshed / loggedOut / refreshFailed).
  /// App con subscribe để navigate hoặc hiện UI.
  static Stream<SsoAuthEvent> get authEvents => _events.stream;

  static bool get isInitialized => _config != null;

  // ─── 1. initialize ───────────────────────────────────────────────────────

  /// Khởi tạo SDK. Phải gọi 1 lần ở đầu app (trước `runApp`).
  ///
  /// [storageOverride] và [apiClientOverride] dùng cho test — production không cần truyền.
  static Future<void> initialize(
    SsoConfig config, {
    SecureTokenStorage? storageOverride,
    SsoApiClient? apiClientOverride,
  }) async {
    _config = config;
    _storage = storageOverride ?? FlutterSecureTokenStorage();
    _api = apiClientOverride ?? SsoApiClient(config: config);
    _log('initialized (appId=${config.appId}, scheme=${config.deepLinkScheme})');
  }

  // ─── 2. handleDeepLink ───────────────────────────────────────────────────

  /// Xử lý deep link nhận từ EMP Mobile.
  ///
  /// - Trả `null` nếu [uri] không phải SSO deep link (path khác, scheme khác).
  /// - Ném [SsoInvalidDeepLinkException] / [SsoAppIdMismatchException] / [SsoAuthException]
  ///   nếu deep link match scheme nhưng có vấn đề.
  /// - Trả [SsoUser] đã đăng nhập khi exchange thành công.
  static Future<SsoUser?> handleDeepLink(Uri uri) async {
    final cfg = _ensureInit();

    if (uri.scheme != cfg.deepLinkScheme) return null;
    // Path có thể là `/sso`, host có thể là `sso` (tùy OS parse) → chấp nhận cả 2.
    final pathSegments = [uri.host, ...uri.pathSegments].where((s) => s.isNotEmpty);
    if (!pathSegments.contains(cfg.ssoPath)) return null;

    final params = DeepLinkParams.parse(uri);
    if (params.appId != cfg.appId) {
      throw SsoAppIdMismatchException(expected: cfg.appId, actual: params.appId);
    }

    final tokens = await _api!.exchangeOneTimeCode(
      code: params.code,
      state: params.state,
      appId: params.appId,
    );
    await _storage!.saveTokens(tokens);

    final user = tokens.user ?? await _fetchAndCacheUser(tokens.accessToken);
    _events.add(SsoAuthEvent.authenticated(user));
    _log('handleDeepLink: authenticated user=${user.id}');
    return user;
  }

  // ─── 3. exchangeOneTimeCode ──────────────────────────────────────────────

  /// Đổi one-time code trực tiếp (dùng khi app con tự parse deep link).
  /// Vẫn validate state ≠ rỗng để chống misuse.
  static Future<TokenResponse> exchangeOneTimeCode(
    String code, {
    required String state,
    String? appId,
  }) async {
    final cfg = _ensureInit();
    if (code.isEmpty) throw const SsoInvalidDeepLinkException('code is empty');
    if (state.isEmpty) throw const SsoInvalidDeepLinkException('state is empty');
    final tokens = await _api!.exchangeOneTimeCode(
      code: code,
      state: state,
      appId: appId ?? cfg.appId,
    );
    await _storage!.saveTokens(tokens);
    if (tokens.user != null) {
      _events.add(SsoAuthEvent.authenticated(tokens.user!));
    }
    return tokens;
  }

  // ─── 4. getAccessToken ───────────────────────────────────────────────────

  /// Lấy access token. Tự động refresh nếu hết hạn (hoặc trong leeway).
  /// Trả `null` nếu chưa đăng nhập.
  /// Ném [SsoSessionExpiredException] nếu refresh thất bại do refresh token hết hạn.
  static Future<String?> getAccessToken() async {
    final cfg = _ensureInit();
    final tokens = await _storage!.readTokens();
    if (tokens == null) return null;

    if (!tokens.isExpired(leewaySeconds: cfg.refreshLeewaySeconds)) {
      return tokens.accessToken;
    }
    final refreshed = await _refreshLocked(tokens.refreshToken);
    return refreshed.accessToken;
  }

  // ─── 5. refreshToken ─────────────────────────────────────────────────────

  /// Force refresh access token. Trả token mới hoặc ném exception.
  static Future<TokenResponse> refreshToken() async {
    _ensureInit();
    final tokens = await _storage!.readTokens();
    if (tokens == null) throw const SsoSessionExpiredException();
    return _refreshLocked(tokens.refreshToken);
  }

  // ─── 6. logout ───────────────────────────────────────────────────────────

  /// Revoke session ở backend (best-effort) và clear local storage.
  /// Không ném exception nếu backend call fail — local session vẫn được clear.
  static Future<void> logout() async {
    _ensureInit();
    final tokens = await _storage!.readTokens();
    if (tokens != null) {
      try {
        await _api!.logout(
          refreshToken: tokens.refreshToken,
          accessToken: tokens.accessToken,
        );
      } catch (e) {
        _log('logout: backend revoke failed (ignored): $e');
      }
    }
    await _storage!.clear();
    _events.add(SsoAuthEvent.loggedOut());
    _log('logout: session cleared');
  }

  // ─── 7. getCurrentUser ───────────────────────────────────────────────────

  /// Lấy user hiện tại. Ưu tiên cache; nếu cache rỗng và có access token thì
  /// gọi `/auth/me` để fetch lại.
  static Future<SsoUser?> getCurrentUser({bool forceRefetch = false}) async {
    _ensureInit();
    if (!forceRefetch) {
      final cached = await _storage!.readUser();
      if (cached != null) return cached;
    }
    final accessToken = await getAccessToken();
    if (accessToken == null) return null;
    return _fetchAndCacheUser(accessToken);
  }

  // ─── internal helpers ────────────────────────────────────────────────────

  static SsoConfig _ensureInit() {
    final cfg = _config;
    if (cfg == null || _api == null || _storage == null) {
      throw const SsoNotInitializedException();
    }
    return cfg;
  }

  static Future<TokenResponse> _refreshLocked(String refreshToken) {
    final inflight = _pendingRefresh;
    if (inflight != null) return inflight;
    final future = _doRefresh(refreshToken);
    _pendingRefresh = future;
    return future.whenComplete(() => _pendingRefresh = null);
  }

  static Future<TokenResponse> _doRefresh(String refreshToken) async {
    try {
      final tokens = await _api!.refresh(refreshToken: refreshToken);
      await _storage!.saveTokens(tokens);
      _events.add(SsoAuthEvent.tokenRefreshed());
      _log('token refreshed');
      return tokens;
    } on SsoSessionExpiredException catch (e) {
      await _storage!.clear();
      _events.add(SsoAuthEvent.refreshFailed(e));
      _events.add(SsoAuthEvent.loggedOut());
      rethrow;
    } catch (e) {
      _events.add(SsoAuthEvent.refreshFailed(e));
      rethrow;
    }
  }

  static Future<SsoUser> _fetchAndCacheUser(String accessToken) async {
    final user = await _api!.getMe(accessToken: accessToken);
    await _storage!.saveUser(user);
    return user;
  }

  static void _log(String message) {
    if (_config?.enableDebugLogging ?? false) {
      developer.log(message, name: 'EmpSso');
    }
  }

  /// Reset toàn bộ state (dùng cho test).
  static Future<void> debugReset() async {
    _api?.close();
    _config = null;
    _api = null;
    _storage = null;
    _pendingRefresh = null;
  }
}
