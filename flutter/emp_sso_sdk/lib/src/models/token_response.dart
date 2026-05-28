import 'package:meta/meta.dart';

import 'sso_user.dart';

@immutable
class TokenResponse {
  const TokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    this.tokenType = 'Bearer',
    this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final String tokenType;
  final SsoUser? user;

  bool isExpired({int leewaySeconds = 0}) {
    final now = DateTime.now().add(Duration(seconds: leewaySeconds));
    return !now.isBefore(accessTokenExpiresAt);
  }

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    final expiresAt = json['accessTokenExpiresAt'];
    final expiresIn = json['expiresIn'];
    final DateTime resolvedExpiry;
    if (expiresAt is String) {
      resolvedExpiry = DateTime.parse(expiresAt);
    } else if (expiresIn is num) {
      resolvedExpiry = DateTime.now().add(Duration(seconds: expiresIn.toInt()));
    } else {
      throw const FormatException(
        'TokenResponse: missing accessTokenExpiresAt or expiresIn',
      );
    }
    return TokenResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      accessTokenExpiresAt: resolvedExpiry,
      tokenType: (json['tokenType'] as String?) ?? 'Bearer',
      user: json['user'] is Map<String, dynamic>
          ? SsoUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
        'tokenType': tokenType,
        if (user != null) 'user': user!.toJson(),
      };
}
