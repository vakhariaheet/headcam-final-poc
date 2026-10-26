import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/hat_device.dart';
import 'package:mobile/models/hat_status.dart';
import 'package:mobile/services/hat_connection_service.dart';
import 'package:mobile/services/hat_ownership_protocol.dart';
import 'package:mobile/state/hat_connection_provider.dart';

import 'fakes/memory_owner_key_store.dart';

/// Hat that behaves like the firmware's ownership rules: one owner key,
/// claims allowed only while [pairingOpen].
class _OwnershipHat implements HatConnectionService {
  _OwnershipHat({this.ownerKey, this.pairingOpen = false});

  String? ownerKey;
  bool pairingOpen;
  final calls = <String>[];
  var _claims = 0;

  @override
  Future<void> connect(String deviceId) async => calls.add('connect');

  @override
  Future<void> disconnect() async => calls.add('disconnect');

  @override
  Future<String> claim() async {
    calls.add('claim');
    if (!pairingOpen) throw const HatOwnershipError('pairing_closed');
    pairingOpen = false;
    return ownerKey = 'key-${++_claims}';
  }

  @override
  Future<void> authenticate(String key) async {
    calls.add('authenticate');
    if (ownerKey == null) throw const HatOwnershipError('no_owner');
    if (key != ownerKey) throw const HatOwnershipError('not_owner');
  }

  @override
  Future<bool> requestBluetoothAccess() async => true;
  @override
  Stream<HatDevice> scan() => const Stream.empty();
  @override
  Future<void> provisionHotspot({
    required String ssid,
    required String passphrase,
    required String band,
  }) async {}
  @override
  Future<void> startStream({String? ingestUrl}) async {}
  @override
  Future<void> stopStream() async {}
  @override
  Stream<HatTelemetry> telemetryStream() => const Stream.empty();
  @override
  Future<HatInfo> readInfo() async => const HatInfo(
    serialNumber: '00E04C000001',
    hardwareModel: 'AMB82_MINI_V1',
    firmwareVersion: '0.2.0',
  );
  @override
  Stream<HatCameraFault> cameraFaults() => const Stream.empty();
  @override
  Future<void> updateFirmware(FirmwareRelease release) async {}
  @override
  Stream<HatUpdateEvent> updateEvents() => const Stream.empty();
}

const _hatId = 'hat-1';

HatDevice _device({bool pairingMode = false, bool owned = false}) => HatDevice(
  id: _hatId,
  name: 'UmpireHat_0001',
  rssi: -50,
  pairingMode: pairingMode,
  owned: owned,
);

Future<HatConnectionState> _connect(
  _OwnershipHat hat,
  MemoryOwnerKeyStore keys,
  HatDevice device,
) async {
  final container = ProviderContainer(
    overrides: [
      hatConnectionServiceProvider.overrideWithValue(hat),
      hatOwnerKeyStoreProvider.overrideWithValue(keys),
    ],
  );
  addTearDown(container.dispose);
  await container.read(hatConnectionProvider.notifier).connect(device);
  return container.read(hatConnectionProvider);
}

void main() {
  group('connect establishes ownership', () {
    test('claims an unowned hat in pairing mode and stores the key', () async {
      final hat = _OwnershipHat(pairingOpen: true);
      final keys = MemoryOwnerKeyStore();

      final state = await _connect(hat, keys, _device(pairingMode: true));

      expect(state.status, HatConnectionStatus.connected);
      expect(state.connectedDevice?.id, _hatId);
      expect(keys.keys[_hatId], 'key-1');
      // Claiming is followed by authentication to get the session key.
      expect(hat.calls, ['connect', 'claim', 'authenticate']);
    });

    test('the owner reconnects with its key and never re-claims', () async {
      final hat = _OwnershipHat(ownerKey: 'key-1', pairingOpen: true);
      final keys = MemoryOwnerKeyStore()..keys[_hatId] = 'key-1';

      final state = await _connect(hat, keys, _device(owned: true));

      expect(state.status, HatConnectionStatus.connected);
      expect(hat.calls, ['connect', 'authenticate']);
      expect(hat.ownerKey, 'key-1'); // pairing mode open, but not consumed
    });

    test('an unowned hat outside pairing mode asks for the button', () async {
      final hat = _OwnershipHat();
      final keys = MemoryOwnerKeyStore();

      final state = await _connect(hat, keys, _device());

      expect(state.status, HatConnectionStatus.notInPairingMode);
      expect(state.connectedDevice, isNull);
      expect(hat.calls, ['connect', 'claim', 'disconnect']);
      expect(keys.keys, isEmpty);
    });

    test('another phone\'s hat is refused without pairing mode', () async {
      final hat = _OwnershipHat(ownerKey: 'their-key');
      final keys = MemoryOwnerKeyStore();

      final state = await _connect(hat, keys, _device(owned: true));

      expect(state.status, HatConnectionStatus.ownedByAnother);
      expect(hat.calls.last, 'disconnect');
      expect(hat.ownerKey, 'their-key');
    });

    test('a stale key is replaced once the button opens pairing', () async {
      final hat = _OwnershipHat(ownerKey: 'their-key', pairingOpen: true);
      final keys = MemoryOwnerKeyStore()..keys[_hatId] = 'old-key';

      final state = await _connect(hat, keys, _device(pairingMode: true));

      expect(state.status, HatConnectionStatus.connected);
      expect(hat.calls, ['connect', 'authenticate', 'claim', 'authenticate']);
      expect(keys.keys[_hatId], 'key-1');
    });

    test('a stale key on a rejected hat reports the other owner', () async {
      final hat = _OwnershipHat(ownerKey: 'their-key');
      final keys = MemoryOwnerKeyStore()..keys[_hatId] = 'old-key';

      final state = await _connect(hat, keys, _device());

      expect(state.status, HatConnectionStatus.ownedByAnother);
      expect(keys.keys[_hatId], 'old-key'); // untouched until a claim succeeds
    });

    test(
      'a factory-reset hat outside pairing mode asks for the button',
      () async {
        final hat = _OwnershipHat();
        final keys = MemoryOwnerKeyStore()..keys[_hatId] = 'old-key';

        final state = await _connect(hat, keys, _device());

        expect(state.status, HatConnectionStatus.notInPairingMode);
      },
    );
  });

  group('wire protocol', () {
    test('advertisement flags decode pairing and owned bits', () {
      HatAdvertisementFlags flags(List<int>? payload) =>
          HatAdvertisementFlags.fromServiceData(payload);

      expect(flags([0x01]).pairingMode, isTrue);
      expect(flags([0x01]).owned, isFalse);
      expect(flags([0x02]).owned, isTrue);
      expect(flags([0x03]).pairingMode && flags([0x03]).owned, isTrue);
      final legacy = flags(null); // firmware without service data
      expect(legacy.pairingMode || legacy.owned, isFalse);
      expect(flags([]).pairingMode, isFalse);
    });

    // Vectors printed by firmware/amb82_hat_native/tests/secure_test.c
    // --vectors, which runs the firmware's own hat_secure.c/hat_crypto.c
    // against the SDK's mbedTLS. Matching them proves the app and the hat
    // derive identical keys and ciphertext.
    const appPrivate =
        '0b30557a9fc4e90e33587da2c7ec11365b80a5caef14395e83a8cdf2173c6186';
    const appPublic =
        '049ed4fbadf89bb1cd3cbdd03737c6b55eb21667ef44baba27dca0daaa8527f1c0'
        '3c52e145bc96ba39bc898fd2bc041afde2fb6c995555554cc3a4e2f2cafe58fc';
    const hatPublic =
        '048e85b51002811319b16650c1731aff753ed169d70072a32c5e97588ebd0c233e'
        'f9d502976c35e766f3d104d2c98ab62ab7dadb687b9c9c5528c59dc6bc2be71d';
    const ownerKey =
        '183ca4f52f4f12a4a932802177f2e8019e0e39fc071392c909d3c6a7d2fbe2ec';
    const nonce = 'f0e1d2c3b4a5968778695a4b3c2d1e0f';
    const sessionKey =
        '02578dbfef95b8e70018f6c4260f657b2f45f0d13a6284fa081416bcd4d53a8a';
    const sealedSetSta =
        'AQIDBAUGBwgJCgsMpETEfUPl0Pi1NdZiQ5EM9W7sEgeJVEYcmEnyd/E6TGAB8LRsMlg43'
        'pMDoPa7FDd6AOxcrIpWIA07ZUvzvro=';

    test('claim derives the same owner key as the firmware', () {
      final pair = HatClaimKeyPair.fromPrivate(
        BigInt.parse(appPrivate, radix: 16),
      );
      expect(hexEncode(pair.publicKey), appPublic);
      expect(hexEncode(pair.deriveOwnerKey(hexDecode(hatPublic))), ownerKey);
    });

    test('session key and sealed SET_STA match the firmware', () {
      final key = hatSessionKey(ownerKeyHex: ownerKey, nonceHex: nonce);
      expect(hexEncode(key), sessionKey);
      expect(
        hatSeal(
          sessionKey: key,
          command: 'SET_STA',
          params: {'ssid': 'test-network', 'pass': 'test-password'},
          iv: List.generate(12, (i) => i + 1),
        ),
        sealedSetSta,
      );
    });

    test('a fresh claim key pair is valid and unique', () {
      final a = HatClaimKeyPair.generate();
      final b = HatClaimKeyPair.generate();
      expect(a.publicKey.length, 65);
      expect(a.publicKey.first, 0x04);
      expect(hexEncode(a.publicKey), isNot(hexEncode(b.publicKey)));
      // A generated pair accepts another valid point as the hat's key.
      expect(hexEncode(a.deriveOwnerKey(b.publicKey)).length, 64);
    });

    test('malformed hat keys are rejected', () {
      final pair = HatClaimKeyPair.generate();
      expect(() => pair.deriveOwnerKey([0x04, 1, 2]), throwsArgumentError);
    });

    test('sealing uses a fresh IV each time', () {
      final key = hatSessionKey(ownerKeyHex: ownerKey, nonceHex: nonce);
      String seal() =>
          hatSeal(sessionKey: key, command: 'SET_STA', params: {'a': 1});
      expect(seal(), isNot(seal()));
    });

    test('owner proof matches an independent HMAC-SHA256', () {
      // Expected value computed with:
      // echo -n f0e1…0f | xxd -r -p |
      //   openssl dgst -sha256 -mac HMAC -macopt hexkey:0001…1f
      expect(
        hatOwnerProof(
          ownerKeyHex:
              '000102030405060708090a0b0c0d0e0f'
              '101112131415161718191a1b1c1d1e1f',
          nonceHex: 'f0e1d2c3b4a5968778695a4b3c2d1e0f',
        ),
        '790212df1ed2fc4d97f9587bc7a55c35fde4b8637b874d750a46f480c8ffb757',
      );
    });
  });
}
