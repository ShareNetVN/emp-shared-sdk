/// Base exception cho mọi lỗi SDK ném ra.
sealed class SsoException implements Exception {
  const SsoException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message${cause != null ? ' (cause: $cause)' : ''}';
}

class SsoNotInitializedException extends SsoException {
  const SsoNotInitializedException()
      : super('EmpSso.initialize(config) chưa được gọi.');
}

class SsoInvalidDeepLinkException extends SsoException {
  const SsoInvalidDeepLinkException(super.message);
}

/// Deep link đúng format nhưng `appId` trong link không khớp với
/// `config.appId` → có thể là deep link của app khác bị OS dispatch nhầm.
class SsoAppIdMismatchException extends SsoException {
  const SsoAppIdMismatchException({required this.expected, required this.actual})
      : super('AppId mismatch: expected "$expected", got "$actual"');
  final String expected;
  final String actual;
}

/// Backend từ chối exchange / refresh.
class SsoAuthException extends SsoException {
  const SsoAuthException(super.message, {this.statusCode, this.errorCode, super.cause});
  final int? statusCode;
  final String? errorCode;
}

/// Hết refresh token / refresh token bị revoke → user phải đăng nhập lại.
class SsoSessionExpiredException extends SsoException {
  const SsoSessionExpiredException()
      : super('Refresh token expired hoặc đã bị revoke. User phải đăng nhập lại.');
}

/// Network failure (timeout, DNS, ...).
class SsoNetworkException extends SsoException {
  const SsoNetworkException(super.message, {super.cause});
}
