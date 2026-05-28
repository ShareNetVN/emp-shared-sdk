# Changelog

## 0.1.0 — 2026-05-28

Initial release.

- `EmpSso.initialize(config)`
- `EmpSso.handleDeepLink(uri)`
- `EmpSso.exchangeOneTimeCode(code)`
- `EmpSso.getAccessToken()` với auto-refresh
- `EmpSso.refreshToken()`
- `EmpSso.logout()` (revoke + clear secure storage)
- `EmpSso.getCurrentUser()`
- `EmpSso.authEvents` stream (authenticated / loggedOut / refreshFailed)
- Secure storage backed by `flutter_secure_storage` (Keystore / Keychain)
