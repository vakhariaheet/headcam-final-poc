import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Real (not mocked) hardware-backed storage for the One-Time Hotspot
/// Profiling flow (spec §4.2). `flutter_secure_storage` uses iOS Keychain /
/// Android Keystore under the hood, so this is genuinely testable without
/// any hat hardware.
class SecureCredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _ssidKey = 'hotspot_ssid';
  static const _passKey = 'hotspot_passphrase';
  static const _bandKey = 'hotspot_band';

  Future<void> saveHotspotProfile({
    required String ssid,
    required String passphrase,
    required String band,
  }) async {
    await _storage.write(key: _ssidKey, value: ssid);
    await _storage.write(key: _passKey, value: passphrase);
    await _storage.write(key: _bandKey, value: band);
  }

  Future<({String ssid, String passphrase, String band})?>
  loadHotspotProfile() async {
    final ssid = await _storage.read(key: _ssidKey);
    final passphrase = await _storage.read(key: _passKey);
    final band = await _storage.read(key: _bandKey);
    if (ssid == null || passphrase == null || band == null) return null;
    return (ssid: ssid, passphrase: passphrase, band: band);
  }

  Future<void> clear() async {
    await _storage.delete(key: _ssidKey);
    await _storage.delete(key: _passKey);
    await _storage.delete(key: _bandKey);
  }
}
