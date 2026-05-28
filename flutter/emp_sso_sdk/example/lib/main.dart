import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:emp_sso_sdk/emp_sso_sdk.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await EmpSso.initialize(
    const SsoConfig(
      baseUrl: 'https://api.emp.company.com',
      // appId: định danh app con (backend dùng để map session).
      appId: 'eoffice',
      // deepLinkScheme: custom URL scheme đăng ký với OS để nhận deep link.
      // Deep link sẽ có dạng: `eoffice://sso?code=...&state=...&appId=eoffice`
      deepLinkScheme: 'eoffice',
      enableDebugLogging: true,
    ),
  );

  runApp(const EOfficeApp());
}

class EOfficeApp extends StatefulWidget {
  const EOfficeApp({super.key});

  @override
  State<EOfficeApp> createState() => _EOfficeAppState();
}

class _EOfficeAppState extends State<EOfficeApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<SsoAuthEvent>? _eventSub;
  final _navKey = GlobalKey<NavigatorState>();

  SsoUser? _user;
  String? _error;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _eventSub = EmpSso.authEvents.listen(_onAuthEvent);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _handleLink(initial);
      } else {
        _user = await EmpSso.getCurrentUser();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _booting = false);
    }

    _linkSub = _appLinks.uriLinkStream.listen(
      _handleLink,
      onError: (Object e) {
        if (mounted) setState(() => _error = e.toString());
      },
    );
  }

  Future<void> _handleLink(Uri uri) async {
    try {
      final user = await EmpSso.handleDeepLink(uri);
      if (user != null && mounted) setState(() => _user = user);
    } on SsoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _onAuthEvent(SsoAuthEvent event) {
    switch (event.type) {
      case SsoAuthEventType.authenticated:
        if (mounted) setState(() => _user = event.user);
      case SsoAuthEventType.loggedOut:
        if (mounted) setState(() => _user = null);
      case SsoAuthEventType.refreshFailed:
        if (mounted) setState(() => _error = 'Session expired, vui lòng đăng nhập lại.');
      case SsoAuthEventType.tokenRefreshed:
        break;
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'eOffice (SSO demo)',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0078D4), useMaterial3: true),
      home: _booting
          ? const _SplashScreen()
          : _user != null
              ? _HomeScreen(user: _user!, onLogout: _doLogout)
              : _LoginPrompt(error: _error),
    );
  }

  Future<void> _doLogout() async {
    await EmpSso.logout();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('eOffice')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Vui lòng mở app này từ EMP Mobile để đăng nhập tự động.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            if (error != null) ...[
              const SizedBox(height: 24),
              Text('Lỗi: $error', style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.user, required this.onLogout});
  final SsoUser user;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('eOffice'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: onLogout),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Xin chào, ${user.fullName ?? user.email}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('User ID: ${user.id}'),
            Text('Email: ${user.email}'),
            if (user.roles.isNotEmpty) Text('Roles: ${user.roles.join(", ")}'),
            const Spacer(),
            FilledButton.icon(
              onPressed: () async {
                final token = await EmpSso.getAccessToken();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Access token: ${_mask(token)}')),
                );
              },
              icon: const Icon(Icons.key),
              label: const Text('Show access token (masked)'),
            ),
          ],
        ),
      ),
    );
  }

  String _mask(String? token) {
    if (token == null || token.length < 8) return '<none>';
    return '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
  }
}
