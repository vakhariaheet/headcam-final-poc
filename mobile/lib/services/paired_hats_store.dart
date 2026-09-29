import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Ids of hats this account has successfully paired with before (BLE
/// connect + Wi-Fi provisioning both completed) — lets Home/Devices offer
/// "choose an existing hat" instead of re-pairing every session. Same
/// `flutter_secure_storage` pattern as [SecureCredentialStore]; a plain
/// comma-joined id list is enough, since a hat's display name always comes
/// fresh from the live BLE scan, never persisted.
class PairedHatsStore {
  PairedHatsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'paired_hat_ids';

  Future<List<String>> loadPairedHatIds() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',');
  }

  Future<void> addPairedHat(String id) async {
    final ids = await loadPairedHatIds();
    if (ids.contains(id)) return;
    await _storage.write(key: _key, value: [...ids, id].join(','));
  }
}
