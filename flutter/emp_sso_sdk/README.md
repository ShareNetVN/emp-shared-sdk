# emp_sso_sdk

Flutter SDK cho **EMP Shared SSO** — cho phép app con tự động đăng nhập từ EMP Mobile thông qua **SSO Handoff** (one-time code + deep link).

> Spec gốc: xem [../../shared-sdk.md](../../shared-sdk.md).

---

## Cài đặt

`pubspec.yaml` của app con:

```yaml
dependencies:
  emp_sso_sdk:
    git:
      url: https://github.com/ShareNetVN/emp-shared-sdk
      path: flutter/emp_sso_sdk
  app_links: ^6.3.2   # để nhận deep link
```

## Khởi tạo

Trong `main.dart`:

```dart
import 'package:emp_sso_sdk/emp_sso_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EmpSso.initialize(const SsoConfig(
    baseUrl: 'https://sso.emp.sharenet.vn',
    appId: 'eoffice',           // backend identifier
    deepLinkScheme: 'eoffice',  // URL scheme đăng ký với OS
  ));
  runApp(const MyApp());
}
```

## Đăng ký URL scheme

### Android — `android/app/src/main/AndroidManifest.xml`

```xml
<activity ...>
  <intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="eoffice" android:host="sso" />
  </intent-filter>
</activity>
```

### iOS — `ios/Runner/Info.plist`

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>eoffice</string>
    </array>
  </dict>
</array>
```

## Xử lý deep link

```dart
final appLinks = AppLinks();

// 1. cold start
final initial = await appLinks.getInitialLink();
if (initial != null) await EmpSso.handleDeepLink(initial);

// 2. warm start
appLinks.uriLinkStream.listen((uri) async {
  await EmpSso.handleDeepLink(uri);
});

// 3. lắng nghe sự kiện auth để navigate
EmpSso.authEvents.listen((event) {
  switch (event.type) {
    case SsoAuthEventType.authenticated: /* push home */
    case SsoAuthEventType.loggedOut:     /* push login */
    case SsoAuthEventType.refreshFailed: /* show toast */
    case SsoAuthEventType.tokenRefreshed: break;
  }
});
```

## API Reference

| Method                                              | Mô tả                                                  |
| --------------------------------------------------- | ------------------------------------------------------ |
| `EmpSso.initialize(config)`                     | Khởi tạo SDK                                           |
| `EmpSso.handleDeepLink(uri)`                    | Xử lý deep link → đăng nhập user                       |
| `EmpSso.exchangeOneTimeCode(code, state:, ...)` | Đổi one-time code trực tiếp (advanced)                 |
| `EmpSso.getAccessToken()`                       | Lấy access token, **tự động refresh** nếu hết hạn      |
| `EmpSso.refreshToken()`                         | Force refresh, trả `TokenResponse` mới                 |
| `EmpSso.logout()`                               | Revoke ở backend (best-effort) + clear secure storage  |
| `EmpSso.getCurrentUser({forceRefetch})`         | Lấy user (ưu tiên cache, fallback `/auth/me`)          |
| `EmpSso.authEvents`                             | `Stream<SsoAuthEvent>` cho lifecycle event             |

## Exceptions

Mọi exception extend `SsoException` (sealed class):

- `SsoNotInitializedException` — chưa gọi `initialize`
- `SsoInvalidDeepLinkException` — deep link thiếu `code` / `state` / `appId`
- `SsoAppIdMismatchException` — `appId` trong link ≠ `config.appId`
- `SsoAuthException` — backend trả 4xx/5xx (có `statusCode`, `errorCode`)
- `SsoSessionExpiredException` — refresh token hết hạn → user phải đăng nhập lại
- `SsoNetworkException` — timeout / DNS / socket lỗi

## Security

- Token lưu bằng `flutter_secure_storage` → Android Keystore + iOS Keychain.
- Không log token / one-time code ra console (chỉ log masked nếu `enableDebugLogging=true`).
- One-time code TTL ≤ 60s, single-use (backend enforce).
- `state` được forward về backend để chống replay (backend kiểm).
- Refresh token được revoke khi `logout()`.

## Backend API contract

App con cần backend implement 4 endpoint sau (xem `lib/src/api/sso_api_client.dart`):

```http
POST /auth/sso-code/exchange    { code, state, appId, deviceId? }  → TokenResponse
POST /auth/refresh              { refreshToken }                    → TokenResponse
POST /auth/logout               { refreshToken }                    → 204
GET  /auth/me                   (Authorization: Bearer ...)         → SsoUser
```

Schema `TokenResponse`:

```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "accessTokenExpiresAt": "2026-05-28T10:00:00Z",   // hoặc "expiresIn": 3600
  "tokenType": "Bearer",
  "user": { "id": "...", "email": "...", "fullName": "...", "roles": ["..."] }
}
```

## Example

Xem thư mục [`example/`](example/) cho minimal app demo full luồng (cold start + warm start + logout).

```bash
cd example
flutter pub get
flutter run
```

## License

Internal — Sharenet / EMP only.
