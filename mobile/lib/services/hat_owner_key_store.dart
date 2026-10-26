import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owner keys for hats this phone has claimed, one per hat id. The key is
/// what proves ownership to the hat; losing it means factory-resetting the
/// hat and claiming it again.
class HatOwnerKeyStore {
  HatOwnerKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _keyFor(String hatId) => 'hat_owner_key_$hatId';

  Future<String?> read(String hatId) => _storage.read(key: _keyFor(hatId));

  Future<void> write(String hatId, String ownerKey) =>
      _storage.write(key: _keyFor(hatId), value: ownerKey);

  Future<void> delete(String hatId) => _storage.delete(key: _keyFor(hatId));
}
