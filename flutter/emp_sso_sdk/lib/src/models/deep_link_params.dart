import 'package:meta/meta.dart';

import '../exceptions/sso_exceptions.dart';

/// Tham số parse được từ deep link `<scheme>://sso?code=...&state=...&appId=...`.
@immutable
class DeepLinkParams {
  const DeepLinkParams({
    required this.code,
    required this.state,
    required this.appId,
  });

  final String code;
  final String state;
  final String appId;

  /// Parse từ [uri]. Ném [SsoInvalidDeepLinkException] nếu thiếu tham số.
  factory DeepLinkParams.parse(Uri uri) {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    final appId = uri.queryParameters['appId'];
    if (code == null || code.isEmpty) {
      throw const SsoInvalidDeepLinkException('Missing "code" param');
    }
    if (state == null || state.isEmpty) {
      throw const SsoInvalidDeepLinkException('Missing "state" param');
    }
    if (appId == null || appId.isEmpty) {
      throw const SsoInvalidDeepLinkException('Missing "appId" param');
    }
    return DeepLinkParams(code: code, state: state, appId: appId);
  }
}
