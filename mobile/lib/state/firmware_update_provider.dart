import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hat_status.dart';
import '../services/app_logger.dart';
import '../services/hat_connection_service.dart';
import 'hat_connection_provider.dart';
import 'user_auth_provider.dart';

enum FirmwareUpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  installing,
  rebooting,
  failed,
}

class FirmwareUpdateState {
  const FirmwareUpdateState({
    this.phase = FirmwareUpdatePhase.idle,
    this.release,
    this.percent = 0,
    this.failure,
  });

  final FirmwareUpdatePhase phase;

  /// The newer release on offer, or being installed.
  final FirmwareRelease? release;

  /// Download progress while [FirmwareUpdatePhase.installing].
  final int percent;

  /// Firmware or app failure code while [FirmwareUpdatePhase.failed]; see
  /// `hatUpdateFailureMessage`.
  final String? failure;
}

/// Checks the backend for newer firmware and installs it on the connected
/// hat. The hat downloads the image itself over Wi-Fi; this only hands it
/// the release (with its SHA-256, sealed) and follows its progress.
class FirmwareUpdateNotifier extends Notifier<FirmwareUpdateState> {
  /// The hat reports every 10%; a ~3 MB image takes seconds over Wi-Fi.
  /// Silence this long means the link or the download is gone.
  static const progressTimeout = Duration(seconds: 60);

  StreamSubscription<HatUpdateEvent>? _events;
  Timer? _watchdog;

  @override
  FirmwareUpdateState build() {
    // A different (or no) hat invalidates whatever was checked.
    ref.watch(hatConnectionProvider.select((s) => s.connectedDevice?.id));
    ref.onDispose(_stopWatching);
    return const FirmwareUpdateState();
  }

  Future<void> check() async {
    final info = ref.read(hatConnectionProvider).info;
    if (info == null) {
      state = const FirmwareUpdateState(
        phase: FirmwareUpdatePhase.failed,
        failure: 'no_info',
      );
      return;
    }
    state = const FirmwareUpdateState(phase: FirmwareUpdatePhase.checking);
    try {
      final token = await ref.read(userSessionStoreProvider).readToken();
      if (token == null) {
        state = const FirmwareUpdateState(
          phase: FirmwareUpdatePhase.failed,
          failure: 'signed_out',
        );
        return;
      }
      final latest = await ref
          .read(deviceApiClientProvider)
          .latestFirmware(token, info.hardwareModel);
      if (latest == null ||
          compareFirmwareVersions(latest.version, info.firmwareVersion) <= 0) {
        state = const FirmwareUpdateState(phase: FirmwareUpdatePhase.upToDate);
      } else {
        state = FirmwareUpdateState(
          phase: FirmwareUpdatePhase.available,
          release: latest,
        );
      }
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Firmware update check failed',
        name: 'FirmwareUpdateNotifier',
        error: e,
        stackTrace: stackTrace,
      );
      state = const FirmwareUpdateState(
        phase: FirmwareUpdatePhase.failed,
        failure: 'check_failed',
      );
    }
  }

  Future<void> install() async {
    final release = state.release;
    if (state.phase != FirmwareUpdatePhase.available || release == null) {
      return;
    }
    final service = ref.read(hatConnectionServiceProvider);
    state = FirmwareUpdateState(
      phase: FirmwareUpdatePhase.installing,
      release: release,
    );
    // Listen before asking so early progress is not missed.
    _stopWatching();
    _armWatchdog(release);
    _events = service.updateEvents().listen(
      (event) => _onEvent(release, event),
      onError: (Object _) => _fail(release, 'ble_disconnected'),
    );
    try {
      await service.updateFirmware(release);
    } on HatUpdateError catch (e) {
      _fail(release, e.reason);
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Firmware update request failed',
        name: 'FirmwareUpdateNotifier',
        error: e,
        stackTrace: stackTrace,
      );
      _fail(release, 'request_failed');
    }
  }

  void _armWatchdog(FirmwareRelease release) {
    _watchdog?.cancel();
    _watchdog = Timer(progressTimeout, () => _fail(release, 'no_progress'));
  }

  void _stopWatching() {
    _watchdog?.cancel();
    _watchdog = null;
    _events?.cancel();
    _events = null;
  }

  void _onEvent(FirmwareRelease release, HatUpdateEvent event) {
    if (state.phase != FirmwareUpdatePhase.installing) return;
    _armWatchdog(release);
    switch (event) {
      case HatUpdateStarted():
        break;
      case HatUpdateDownloading(:final percent):
        state = FirmwareUpdateState(
          phase: FirmwareUpdatePhase.installing,
          release: release,
          percent: percent,
        );
      case HatUpdateRebooting():
        state = FirmwareUpdateState(
          phase: FirmwareUpdatePhase.rebooting,
          release: release,
          percent: 100,
        );
        _stopWatching();
      case HatUpdateFailed(:final reason):
        _fail(release, reason);
    }
  }

  void _fail(FirmwareRelease release, String reason) {
    if (state.phase != FirmwareUpdatePhase.installing) return;
    _stopWatching();
    state = FirmwareUpdateState(
      phase: FirmwareUpdatePhase.failed,
      release: release,
      failure: reason,
    );
  }
}

final firmwareUpdateProvider =
    NotifierProvider<FirmwareUpdateNotifier, FirmwareUpdateState>(
      FirmwareUpdateNotifier.new,
    );
