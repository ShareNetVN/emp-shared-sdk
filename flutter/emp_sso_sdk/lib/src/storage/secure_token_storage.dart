import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/sso_user.dart';
import '../models/token_response.dart';

/// Abstraction để test có thể swap bằng in-memory fake.
abstract class SecureTokenStorage {
  Future<void> saveTokens(TokenResponse tokens);
  Future<TokenResponse?> readTokens();
  Future<void> saveUser(SsoUser user);
  Future<SsoUser?> readUser();
  Future<void> clear();
}

class FlutterSecureTokenStorage implements SecureTokenStorage {
  FlutterSecureTokenStorage({FlutterSecureStorage? storage, String namespace = 'emp_sso'})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        _tokensKey = '${namespace}_tokens_v1',
        _userKey = '${namespace}_user_v1';

  final FlutterSecureStorage _storage;
  final String _tokensKey;
  final String _userKey;

  @override
  Future<void> saveTokens(TokenResponse tokens) async {
    await _storage.write(key: _tokensKey, value: jsonEncode(tokens.toJson()));
    final user = tokens.user;
    if (user != null) {
      await saveUser(user);
    }
  }

  @override
  Future<TokenResponse?> readTokens() async {
    final raw = await _storage.read(key: _tokensKey);
    if (raw == null) return null;
    try {
      return TokenResponse.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _storage.delete(key: _tokensKey);
      return null;
    }
  }

  @override
  Future<void> saveUser(SsoUser user) async {
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  @override
  Future<SsoUser?> readUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    try {
      return SsoUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _storage.delete(key: _userKey);
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokensKey);
    await _storage.delete(key: _userKey);
  }
}
