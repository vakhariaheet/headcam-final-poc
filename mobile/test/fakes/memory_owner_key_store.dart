import 'package:mobile/services/hat_owner_key_store.dart';

/// In-memory [HatOwnerKeyStore]; widget tests have no secure-storage plugin.
class MemoryOwnerKeyStore extends HatOwnerKeyStore {
  final keys = <String, String>{};

  @override
  Future<String?> read(String hatId) async => keys[hatId];

  @override
  Future<void> write(String hatId, String ownerKey) async =>
      keys[hatId] = ownerKey;

  @override
  Future<void> delete(String hatId) async => keys.remove(hatId);
}
