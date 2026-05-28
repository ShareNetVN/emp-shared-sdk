# EMP Shared SSO SDK

Thư viện dùng chung cho phép các ứng dụng con trong hệ sinh thái **Enterprise Mobile Platform (EMP)** tích hợp **Single Sign-On (SSO)** với **EMP Mobile** thông qua cơ chế **SSO Handoff** (one-time code + deep link).

> Spec gốc: [shared-sdk.md](../EMP/shared-sdk.md) (hoặc file `shared-sdk.md` trong workspace).

---

## 1. Mục tiêu

- Cho phép user **đăng nhập 1 lần** ở EMP Mobile và tự động đăng nhập sang các app con (eOffice, Inspection, HR, Approval, ...).
- App con chỉ cần thay đổi **tối thiểu** code (chỉ cần forward deep link cho SDK).
- **Không truyền access token trực tiếp qua URL** — chỉ truyền one-time code (TTL 30–60s, single-use).
- Token lưu trong **secure storage** theo từng nền tảng.

---

## 2. Cấu trúc repo

```
emp-shared-sdk/
├── CLAUDE.md                  ← file này
├── shared-sdk.md              ← spec gốc (tiếng Việt)
│
├── flutter/
│   └── emp_sso_sdk/           ← Flutter package (DONE)
│       ├── lib/
│       │   ├── emp_sso_sdk.dart
│       │   └── src/
│       │       ├── emp_sso.dart
│       │       ├── config/
│       │       ├── models/
│       │       ├── storage/
│       │       ├── api/
│       │       └── exceptions/
│       ├── example/
│       ├── pubspec.yaml
│       └── README.md
│
├── android/                   ← Android Native SDK (TODO)
├── ios/                       ← iOS Native SDK (TODO)
├── react-native/              ← React Native wrapper (TODO)
└── web/                       ← Web SDK (TODO)
```

---

## 3. Core API (chung cho mọi platform)

| Function                    | Mô tả                                                |
| --------------------------- | ---------------------------------------------------- |
| `initialize(config)`        | Khởi tạo SDK với cấu hình hệ thống (baseUrl, appId)  |
| `handleDeepLink(uri)`       | Xử lý deep link nhận từ EMP Mobile                   |
| `exchangeOneTimeCode(code)` | Đổi one-time code lấy access + refresh token         |
| `getAccessToken()`          | Lấy access token hiện tại (auto-refresh nếu hết hạn) |
| `refreshToken()`            | Gia hạn access token                                 |
| `logout()`                  | Logout và xóa session (revoke ở backend)             |
| `getCurrentUser()`          | Lấy thông tin user hiện tại                          |

---

## 4. Deep Link Format

```
<child-app-scheme>://sso?code=<one_time_code>&state=<state>&appId=<app_id>
```

VD: `eoffice://sso?code=abc123&state=xyz&appId=eoffice`

| Param   | Mô tả                                  |
| ------- | -------------------------------------- |
| `code`  | One-time code (TTL 30–60s, single-use) |
| `state` | Chống replay attack                    |
| `appId` | Định danh app con                      |

---

## 5. Backend APIs (sub-app gọi)

```http
POST /auth/sso-code/exchange   ← đổi one-time code → tokens
POST /auth/refresh             ← gia hạn access token
POST /auth/logout              ← revoke session
GET  /auth/me                  ← lấy user hiện tại
```

> `POST /auth/sso-code/create` chỉ EMP Mobile gọi, không nằm trong SDK con.

---

## 6. SSO Handoff Flow

```text
[EMP Mobile]
   │  1. User đã đăng nhập, đã có session token của EMP Mobile
   │  2. User tap icon "eOffice" trong launcher của EMP Mobile
   │  3. EMP Mobile gọi POST /auth/sso-code/create
   │     Headers: Authorization: Bearer <EMP_Mobile_access_token>
   │     Body:    { "appId": "eoffice", "deviceId": "<device-uuid>" }
   │     ←      { "code": "A7Bx9Kq2pL", "state": "r4nd0mNonce", "expiresIn": 60 }
   │  4. EMP Mobile build deep link và mở qua url_launcher / Intent:
   │     eoffice://sso?code=A7Bx9Kq2pL&state=r4nd0mNonce&appId=eoffice
   ▼
[OS dispatch theo URL scheme đã đăng ký]
   ▼
[App con — eOffice]
   │  5. OS launch eOffice (cold start hoặc bring to foreground)
   │     và pass deep link URI cho app
   │  6. eOffice gọi EmpSso.handleDeepLink(uri)
   │     └─ SDK parse code/state/appId
   │     └─ SDK gọi POST /auth/sso-code/exchange { code, state, appId, deviceId }
   │     ←      { accessToken, refreshToken, expiresIn, user }
   │     └─ Lưu access + refresh token vào secure storage (Keystore/Keychain)
   │     └─ Emit SsoAuthEvent.authenticated(user)
   │  7. eOffice listen authEvents → navigate vào home (user đã đăng nhập)
   ▼
[Authenticated session — eOffice có access token riêng, độc lập với EMP Mobile]
```

### 6.1 EMP Mobile sinh deep link như thế nào (parent side)

> SDK này chỉ phục vụ **app con**. Code dưới đây là phía **EMP Mobile** (cha) để minh hoạ — không nằm trong package `emp_sso_sdk`.

```dart
// Trong EMP Mobile khi user tap icon eOffice:
Future<void> openSubApp({required String appId, required String scheme}) async {
  // 1. Xin one-time code từ backend (EMP Mobile đã có sẵn session token)
  final res = await http.post(
    Uri.parse('https://sso.emp.sharenet.vn/auth/sso-code/create'),
    headers: {
      'Authorization': 'Bearer $empMobileAccessToken',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'appId': appId, 'deviceId': await getDeviceId()}),
  );
  final data = jsonDecode(res.body) as Map<String, dynamic>;

  // 2. Build deep link
  final deepLink = Uri(
    scheme: scheme,                              // 'eoffice'
    host: 'sso',
    queryParameters: {
      'code': data['code'] as String,            // 'A7Bx9Kq2pL'
      'state': data['state'] as String,          // 'r4nd0mNonce'
      'appId': appId,                            // 'eoffice'
    },
  );
  // → eoffice://sso?code=A7Bx9Kq2pL&state=r4nd0mNonce&appId=eoffice

  // 3. Mở deep link — OS sẽ launch app eOffice nếu đã cài, hoặc mở store
  final launched = await url_launcher.launchUrl(
    deepLink,
    mode: LaunchMode.externalApplication,
  );
  if (!launched) {
    // Fallback: chưa cài eOffice → mở store (deep link → app store ID đã đăng ký)
  }
}
```

| Bước | Ai làm           | Gọi gì                                       | Trả gì                      |
| ---- | ---------------- | -------------------------------------------- | --------------------------- |
| 3    | EMP Mobile       | `POST /auth/sso-code/create`                 | `code` + `state` (TTL 60s)  |
| 4    | EMP Mobile       | `url_launcher.launchUrl(deepLink)`           | OS dispatch                 |
| 6    | App con (SDK)    | `EmpSso.handleDeepLink(uri)` → backend exchange | `accessToken` + `refreshToken` + `user` |

---

## 7. Secure Storage theo nền tảng

| Platform     | Secure Storage                          |
| ------------ | --------------------------------------- |
| Android      | EncryptedSharedPreferences / Keystore   |
| iOS          | Keychain                                |
| React Native | expo-secure-store / react-native-keychain |
| Flutter      | `flutter_secure_storage`                |
| Web          | httpOnly cookie (preferred) / IndexedDB |

---

## 8. Security checklist (bắt buộc)

- [x] One-time code single-use, TTL 30–60s
- [x] Code bind với `userId + appId + deviceId` (backend enforce)
- [x] `state` / `nonce` chống replay
- [x] **Không** truyền access token qua URL
- [x] Token chỉ lưu trong secure storage
- [x] Refresh token revoke khi logout
- [x] Auto-refresh access token khi hết hạn

---

## 9. Quy ước code

- **Ngôn ngữ giao tiếp**: tiếng Việt trong PR description và doc comments mô tả; identifier giữ tiếng Anh.
- **Versioning**: SemVer (major.minor.patch). Mọi breaking change phải bump major và ghi vào `CHANGELOG.md` của package tương ứng.
- **Package name chung**: `emp_sso_sdk` (Flutter), `@emp/sso-sdk` (RN/Web), `com.emp.sso` (Android), `EmpSsoSDK` (iOS).
- **Không log token / one-time code** ra console. Khi cần debug dùng masked (`abc***xyz`).

---

## 10. Trạng thái implementation

| Platform     | Status     | Path                          |
| ------------ | ---------- | ----------------------------- |
| Flutter      | ✅ Done    | [flutter/emp_sso_sdk/](flutter/emp_sso_sdk/) |
| Android      | ⏳ TODO    | `android/`                    |
| iOS          | ⏳ TODO    | `ios/`                        |
| React Native | ⏳ TODO    | `react-native/`               |
| Web          | ⏳ TODO    | `web/`                        |

---

## 11. Test integration nhanh (Flutter)

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EmpSso.initialize(SsoConfig(
    baseUrl: 'https://sso.emp.sharenet.vn',
    appId: 'eoffice',           // backend identifier
    deepLinkScheme: 'eoffice',  // URL scheme đăng ký với OS
  ));
  runApp(MyApp());
}

// Trong widget xử lý deep link:
final user = await EmpSso.handleDeepLink(uri);
if (user != null) navigateToHome();
```

Xem chi tiết: [flutter/emp_sso_sdk/README.md](flutter/emp_sso_sdk/README.md) và [flutter/emp_sso_sdk/example/](flutter/emp_sso_sdk/example/).
