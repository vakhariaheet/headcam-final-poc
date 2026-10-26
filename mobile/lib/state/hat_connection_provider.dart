import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hat_device.dart';
import '../models/hat_status.dart';
import '../services/app_logger.dart';
import '../services/device_api_client.dart';
import '../services/hat_connection_service.dart';
import '../services/hat_owner_key_store.dart';
import '../services/paired_hats_store.dart';
import '../services/real_hat_connection_service.dart';
import 'user_auth_provider.dart';

final pairedHatsStoreProvider = Provider<PairedHatsStore>(
  (ref) => PairedHatsStore(),
);

final hatOwnerKeyStoreProvider = Provider<HatOwnerKeyStore>(
  (ref) => HatOwnerKeyStore(),
);

final deviceApiClientProvider = Provider<DeviceApiClient>(
  (ref) => DeviceApiClient(),
);

/// Ids of hats this account has successfully paired with before — see
/// [PairedHatsStore]. Home/Devices use this to decide whether "Choose
/// Existing Hat" is even worth offering, and [SelectHatScreen] uses it to
/// filter a live scan down to hats already known.
final pairedHatIdsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(pairedHatsStoreProvider).loadPairedHatIds(),
);

/// Backed by [RealHatConnectionService] talking to the GATT service
/// `firmware/amb82_hat_native` advertises (spec §4). Nothing else in
/// state/ or screens/ needs to know this isn't the mock anymore.
final hatConnectionServiceProvider = Provider<HatConnectionService>((ref) {
  final service = RealHatConnectionService();
  ref.onDispose(service.disconnect);
  return service;
});

enum HatConnectionStatus {
  idle,
  scanning,
  connecting,
  connected,
  timedOut,

  /// Unowned hat whose pairing window is closed: hold its button 3 s.
  notInPairingMode,

  /// Another phone owns this hat. Its pairing mode must be opened to claim it.
  ownedByAnother,
  provisioning,
  provisioned,
}

class HatConnectionState {
  const HatConnectionState({
    this.status = HatConnectionStatus.idle,
    this.discovered = const [],
    this.connectedDevice,
    this.info,
  });

  final HatConnectionStatus status;
  final List<HatDevice> discovered;
  final HatDevice? connectedDevice;

  /// What the connected hat reported about itself; null until read, and
  /// for firmware that predates `INFO`.
  final HatInfo? info;

  HatConnectionState copyWith({
    HatConnectionStatus? status,
    List<HatDevice>? discovered,
    HatDevice? connectedDevice,
    HatInfo? info,
    bool clearInfo = false,
  }) => HatConnectionState(
    status: status ?? this.status,
    discovered: discovered ?? this.discovered,
    connectedDevice: connectedDevice ?? this.connectedDevice,
    info: clearInfo ? null : info ?? this.info,
  );
}

/// Drives Screens 2 & 3 (spec §6.2): BLE discovery, connect-with-timeout,
/// and hotspot provisioning — all against [hatConnectionServiceProvider],
/// currently the mock.
class HatConnectionNotifier extends Notifier<HatConnectionState> {
  @override
  HatConnectionState build() => const HatConnectionState();

  Future<bool> requestBluetoothAccess() async {
    try {
      return await ref
          .read(hatConnectionServiceProvider)
          .requestBluetoothAccess();
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Bluetooth permission request failed',
        name: 'HatConnectionNotifier',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> startScan() async {
    state = state.copyWith(
      status: HatConnectionStatus.scanning,
      discovered: const [],
    );
    final service = ref.read(hatConnectionServiceProvider);
    try {
      await for (final device in service.scan()) {
        state = state.copyWith(discovered: [...state.discovered, device]);
      }
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Bluetooth scan failed',
        name: 'HatConnectionNotifier',
        error: e,
        stackTrace: stackTrace,
      );
    }
    if (state.status == HatConnectionStatus.scanning) {
      state = state.copyWith(status: HatConnectionStatus.idle);
    }
  }

  Future<void> connect(HatDevice device) async {
    state = state.copyWith(status: HatConnectionStatus.connecting);
    final service = ref.read(hatConnectionServiceProvider);
    try {
      await service
          .connect(device.id)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw HatConnectionTimeout(device.id),
          );
      final outcome = await _establishOwnership(service, device);
      if (outcome != HatConnectionStatus.connected) {
        await service.disconnect();
      }
      state = state.copyWith(
        status: outcome,
        connectedDevice: outcome == HatConnectionStatus.connected
            ? device
            : null,
        clearInfo: true,
      );
      if (outcome == HatConnectionStatus.connected) unawaited(refreshInfo());
    } on HatConnectionTimeout {
      state = state.copyWith(status: HatConnectionStatus.timedOut);
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Bluetooth connection failed',
        name: 'HatConnectionNotifier',
        error: e,
        stackTrace: stackTrace,
      );
      state = state.copyWith(status: HatConnectionStatus.timedOut);
    }
  }

  /// Proves ownership with this phone's stored key, or claims the hat when
  /// its pairing window is open. Claiming replaces any previous owner, so
  /// it is only attempted once the stored key (if any) has been rejected.
  Future<HatConnectionStatus> _establishOwnership(
    HatConnectionService service,
    HatDevice device,
  ) async {
    final keys = ref.read(hatOwnerKeyStoreProvider);
    final storedKey = await keys.read(device.id);
    var ownedElsewhere = device.owned;
    if (storedKey != null) {
      try {
        await service.authenticate(storedKey);
        return HatConnectionStatus.connected;
      } on HatOwnershipError catch (e) {
        // `no_owner`: the hat was factory-reset, so this key is useless.
        ownedElsewhere = e.reason == 'not_owner';
        AppLogger.warning(
          'Stored owner key rejected (${e.reason})',
          name: 'HatConnectionNotifier',
        );
      }
    }
    try {
      final ownerKey = await service.claim();
      await keys.write(device.id, ownerKey);
      // Claiming only establishes the key; the link authenticates like any
      // returning owner to get the session key that seals credentials.
      await service.authenticate(ownerKey);
      return HatConnectionStatus.connected;
    } on HatOwnershipError catch (e) {
      if (e.reason != 'pairing_closed') rethrow;
      return ownedElsewhere
          ? HatConnectionStatus.ownedByAnother
          : HatConnectionStatus.notInPairingMode;
    }
  }

  /// Reads the connected hat's [HatInfo], then links the hat to the
  /// signed-in account in the background. Neither step blocks using the hat:
  /// older firmware has no `INFO`, and the backend may be unreachable.
  Future<void> refreshInfo() async {
    final device = state.connectedDevice;
    if (device == null) return;
    final HatInfo info;
    try {
      info = await ref.read(hatConnectionServiceProvider).readInfo();
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Reading hat info failed',
        name: 'HatConnectionNotifier',
        error: e,
        stackTrace: stackTrace,
      );
      return;
    }
    if (state.connectedDevice?.id != device.id) return;
    state = state.copyWith(info: info);
    await _linkToAccount(info);
  }

  Future<void> _linkToAccount(HatInfo info) async {
    try {
      final token = await ref.read(userSessionStoreProvider).readToken();
      if (token == null) return;
      await ref.read(deviceApiClientProvider).linkDevice(token, info);
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Linking hat to account failed',
        name: 'HatConnectionNotifier',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> provisionHotspot({
    required String ssid,
    required String passphrase,
    required String band,
  }) async {
    state = state.copyWith(status: HatConnectionStatus.provisioning);
    final service = ref.read(hatConnectionServiceProvider);
    try {
      await service.provisionHotspot(
        ssid: ssid,
        passphrase: passphrase,
        band: band,
      );
      state = state.copyWith(status: HatConnectionStatus.provisioned);
      // Pairing = BLE connect + Wi-Fi provisioning, both done — this hat is
      // now a known/paired hat, offered on future launches without
      // re-pairing.
      final device = state.connectedDevice;
      if (device != null) {
        await ref.read(pairedHatsStoreProvider).addPairedHat(device.id);
        ref.invalidate(pairedHatIdsProvider);
      }
      return true;
    } catch (e, stackTrace) {
      // ssid/passphrase deliberately left out of the log line — no reason
      // to persist Wi-Fi credentials in log output.
      AppLogger.warning(
        'provisionHotspot failed (band: $band)',
        name: 'HatConnectionNotifier',
        error: e,
        stackTrace: stackTrace,
      );
      state = state.copyWith(status: HatConnectionStatus.connected);
      return false;
    }
  }
}

final hatConnectionProvider =
    NotifierProvider<HatConnectionNotifier, HatConnectionState>(
      HatConnectionNotifier.new,
    );

/// Live telemetry feed for Screen 6 (spec §7.2 `telemetry_samples`).
/// Resubscribes when the connected hat changes, since the service can only
/// listen once its status characteristic has been discovered.
final hatTelemetryProvider = StreamProvider<HatTelemetry>((ref) {
  final service = ref.watch(hatConnectionServiceProvider);
  ref.watch(hatConnectionProvider.select((s) => s.connectedDevice?.id));
  return service.telemetryStream();
});

/// Live camera failures from the connected hat. The hat reboots itself to
/// recover, at most [HatCameraFault.maxRestarts] times in a row.
final hatCameraFaultProvider = StreamProvider<HatCameraFault>((ref) {
  final service = ref.watch(hatConnectionServiceProvider);
  ref.watch(hatConnectionProvider.select((s) => s.connectedDevice?.id));
  return service.cameraFaults();
});
