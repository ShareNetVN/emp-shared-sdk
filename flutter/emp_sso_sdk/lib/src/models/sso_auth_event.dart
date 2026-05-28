import 'package:meta/meta.dart';

import 'sso_user.dart';

enum SsoAuthEventType { authenticated, tokenRefreshed, loggedOut, refreshFailed }

@immutable
class SsoAuthEvent {
  const SsoAuthEvent._(this.type, {this.user, this.error});

  final SsoAuthEventType type;
  final SsoUser? user;
  final Object? error;

  factory SsoAuthEvent.authenticated(SsoUser user) =>
      SsoAuthEvent._(SsoAuthEventType.authenticated, user: user);

  factory SsoAuthEvent.tokenRefreshed() =>
      const SsoAuthEvent._(SsoAuthEventType.tokenRefreshed);

  factory SsoAuthEvent.loggedOut() =>
      const SsoAuthEvent._(SsoAuthEventType.loggedOut);

  factory SsoAuthEvent.refreshFailed(Object error) =>
      SsoAuthEvent._(SsoAuthEventType.refreshFailed, error: error);

  @override
  String toString() => 'SsoAuthEvent($type)';
}
