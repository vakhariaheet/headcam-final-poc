import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hat_device.dart';
import '../services/app_logger.dart';
import '../services/hat_connection_service.dart';
import '../services/paired_hats_store.dart';
import '../services/real_hat_connection_service.dart';

final pairedHatsStoreProvider = Provider<PairedHatsStore>(
  (ref) => PairedHatsStore(),
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
  provisioning,
  provisioned,
}

class HatConnectionState {
  const HatConnectionState({
    this.status = HatConnectionStatus.idle,
    this.discovered = const [],
    this.connectedDevice,
  });

  final HatConnectionStatus status;
  final List<HatDevice> discovered;
  final HatDevice? connectedDevice;

  HatConnectionState copyWith({
    HatConnectionStatus? status,
    List<HatDevice>? discovered,
    HatDevice? connectedDevice,
  }) => HatConnectionState(
    status: status ?? this.status,
    discovered: discovered ?? this.discovered,
    connectedDevice: connectedDevice ?? this.connectedDevice,
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
      state = state.copyWith(
        status: HatConnectionStatus.connected,
        connectedDevice: device,
      );
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
final hatTelemetryProvider = StreamProvider<HatTelemetry>((ref) {
  final service = ref.watch(hatConnectionServiceProvider);
  return service.telemetryStream();
});
