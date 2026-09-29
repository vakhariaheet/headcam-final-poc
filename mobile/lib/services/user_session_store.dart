import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Real hardware-backed storage for the signed-in session JWT, separate
/// from [SecureCredentialStore] (which holds the hotspot profile) to keep
/// the two concerns independent.
class UserSessionStore {
  UserSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _tokenKey = 'session_token';

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> clear() => _storage.delete(key: _tokenKey);
}
