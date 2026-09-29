import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether the signed-in account has connected each broadcast channel —
/// persisted so OAuth (still stubbed, see broadcast_channels_provider.dart)
/// only has to happen once per account, not once per broadcast. Same
/// pattern as [SecureCredentialStore]/[PairedHatsStore].
class ChannelConnectionStore {
  ChannelConnectionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _googleKey = 'channel_google_connected';
  static const _metaKey = 'channel_meta_connected';

  Future<({bool google, bool meta})> load() async {
    final google = await _storage.read(key: _googleKey);
    final meta = await _storage.read(key: _metaKey);
    return (google: google == 'true', meta: meta == 'true');
  }

  Future<void> setGoogleConnected(bool connected) =>
      _storage.write(key: _googleKey, value: connected.toString());

  Future<void> setMetaConnected(bool connected) =>
      _storage.write(key: _metaKey, value: connected.toString());
}
