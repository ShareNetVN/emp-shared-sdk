import 'package:meta/meta.dart';

/// Cấu hình khởi tạo cho [EmpSso].
@immutable
class SsoConfig {
  const SsoConfig({
    required this.baseUrl,
    required this.appId,
    required this.deepLinkScheme,
    this.ssoPath = 'sso',
    this.refreshLeewaySeconds = 30,
    this.requestTimeout = const Duration(seconds: 15),
    this.enableDebugLogging = false,
  });

  /// Base URL của Authentication Service (vd: `https://api.emp.company.com`).
  /// Không chứa trailing slash.
  final String baseUrl;

  /// Định danh app con — phải khớp với `appId` mà EMP Mobile dùng khi tạo
  /// one-time code, và phải khớp với `appId` query param trong deep link.
  /// VD: `eoffice`, `inspection`, `hr`.
  final String appId;

  /// Custom URL scheme đã đăng ký với OS (vd: `eoffice`).
  /// Phải unique trên device — không trùng với scheme của app khác đã cài.
  /// Deep link sẽ có dạng `<deepLinkScheme>://<ssoPath>?...`.
  final String deepLinkScheme;

  /// Path segment của deep link SSO. Default `sso` → `eoffice://sso?...`.
  final String ssoPath;

  /// Số giây trước khi access token expired thì coi như expired và auto-refresh.
  /// Tránh race condition khi token gần hết hạn.
  final int refreshLeewaySeconds;

  /// Timeout cho mọi HTTP request đến Authentication Service.
  final Duration requestTimeout;

  /// Bật log debug (KHÔNG log token / one-time code, chỉ log event).
  final bool enableDebugLogging;

  String get exchangeUrl => '$baseUrl/auth/sso-code/exchange';
  String get refreshUrl => '$baseUrl/auth/refresh';
  String get logoutUrl => '$baseUrl/auth/logout';
  String get meUrl => '$baseUrl/auth/me';
}
