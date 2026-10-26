import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cloud_status.dart';
import '../services/cloud_control_api_client.dart';
import '../services/user_session_store.dart';
import 'user_auth_provider.dart';
import 'scoreboard_provider.dart';
import 'hat_connection_provider.dart';

/// Override at build/run time with `--dart-define=CLOUD_BASE_URL=...` — see
/// authApiClientProvider's BACKEND_BASE_URL for the same pattern.
const _cloudBaseUrl = String.fromEnvironment(
  'CLOUD_BASE_URL',
  defaultValue: 'http://217.216.58.69:4100',
);
const _ingestUrl = String.fromEnvironment(
  'HAT_INGEST_URL',
  defaultValue: 'rtmp://217.216.58.69:1935/live/hat',
);

final cloudControlApiClientProvider = Provider<CloudControlApiClient>(
  (ref) => CloudControlApiClient(
    baseUrl: _cloudBaseUrl.isEmpty ? null : _cloudBaseUrl,
  ),
);

class BroadcastSessionState {
  const BroadcastSessionState({
    this.isLive = false,
    this.elapsed = Duration.zero,
    this.sessionId,
    this.isConnecting = false,
    this.error,
  });

  final bool isLive;
  final Duration elapsed;
  final String? sessionId;
  final bool isConnecting;
  final String? error;

  /// Only for the once-a-second tick, which never needs to touch the other
  /// fields — every other transition builds a fresh [BroadcastSessionState]
  /// directly, same as [UserAuthNotifier] does for its own state.
  BroadcastSessionState copyWith({Duration? elapsed}) => BroadcastSessionState(
    isLive: isLive,
    elapsed: elapsed ?? this.elapsed,
    sessionId: sessionId,
  );
}

/// Screen 6's live match duration timer and emergency kill switch (spec
/// §6.2), now backed by real cloud sessions (`cloud/worker/`) instead of
/// local-only state. Battery/temperature/bitrate readouts come separately
/// from [hatTelemetryProvider] in hat_connection_provider.dart.
class BroadcastSessionNotifier extends Notifier<BroadcastSessionState> {
  Timer? _ticker;
  int _operation = 0;
  bool _stopping = false;
  bool _disposed = false;
  late final CloudControlApiClient _cloud = ref.read(
    cloudControlApiClientProvider,
  );
  late final UserSessionStore _sessionStore = ref.read(
    userSessionStoreProvider,
  );

  @override
  BroadcastSessionState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      ++_operation;
      _ticker?.cancel();
    });
    return const BroadcastSessionState();
  }

  Future<bool> goLive() async {
    if (_stopping || state.isConnecting || state.isLive) return false;
    final operation = ++_operation;
    state = const BroadcastSessionState(isConnecting: true);
    final hat = ref.read(hatConnectionServiceProvider);
    String? sessionId;
    var hatStartRequested = false;
    try {
      final token = await _sessionStore.readToken();
      if (operation != _operation) return false;
      if (token == null) {
        throw StateError('You need to be signed in to go live.');
      }
      hatStartRequested = true;
      await hat.startStream(ingestUrl: _ingestUrl.isEmpty ? null : _ingestUrl);
      if (operation != _operation) return false;
      sessionId = await _cloud.startSession(
        token,
        scoreboard: ref.read(scoreboardProvider),
        target: ref.read(broadcastTargetProvider),
        title: ref.read(broadcastTitleProvider),
        privacy: ref.read(broadcastPrivacyProvider),
      );
      if (operation != _operation) {
        await _cloud.stopSession(token, sessionId);
        return false;
      }
      state = BroadcastSessionState(isLive: true, sessionId: sessionId);
      _startTicker();
      return true;
    } catch (error) {
      if (operation != _operation) return false;
      String? stopError;
      try {
        if (hatStartRequested) await hat.stopStream();
      } catch (_) {
        stopError =
            'Could not confirm the hat stopped. Reconnect or power it off.';
      }
      if (operation == _operation) {
        state = BroadcastSessionState(
          error:
              stopError ??
              (error is CloudControlApiException
                  ? error.message
                  : error.toString()),
        );
      }
      return false;
    }
  }

  Future<void> updateScoreboard(Map<String, dynamic> scoreboard) async {
    final id = state.sessionId;
    final token = await _sessionStore.readToken();
    if (id == null || token == null) throw StateError('No active broadcast.');
    await _cloud.updateScoreboard(token, id, scoreboard);
  }

  /// Stop the hat and cloud independently: failure of either must not prevent
  /// attempting the other. UI leaves live immediately; failures remain visible.
  Future<void> endBroadcast() async {
    if (_stopping) return;
    _stopping = true;
    ++_operation;
    final sessionId = state.sessionId;
    final elapsed = state.elapsed;
    _ticker?.cancel();
    state = BroadcastSessionState(elapsed: elapsed);
    final errors = <String>[];
    Future<void> stopHat() async {
      try {
        await ref.read(hatConnectionServiceProvider).stopStream();
      } catch (_) {
        errors.add(
          'Could not confirm the hat stopped. Reconnect or power it off.',
        );
      }
    }

    Future<void> stopCloud() async {
      if (sessionId == null) return;
      try {
        final token = await _sessionStore.readToken();
        if (token == null) throw StateError('Not signed in');
        await _cloud.stopSession(token, sessionId);
      } catch (error) {
        errors.add(
          error is CloudControlApiException
              ? error.message
              : 'Could not confirm the cloud session stopped.',
        );
      }
    }

    try {
      await Future.wait([stopHat(), stopCloud()]);
      if (!_disposed) {
        state = BroadcastSessionState(
          elapsed: elapsed,
          error: errors.isEmpty ? null : errors.join(' '),
        );
      }
    } finally {
      _stopping = false;
    }
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(
        elapsed: state.elapsed + const Duration(seconds: 1),
      );
    });
  }

  /// Called from [LiveBroadcastScreen]'s `ref.listen(cloudStatusProvider,
  /// ...)` — kept out of this notifier's own [build] deliberately.
  /// [cloudStatusProvider] watches this provider's `sessionId`, so a
  /// `ref.listen(cloudStatusProvider, ...)` from inside this notifier's
  /// build() back onto a provider that watches this one is a genuine
  /// circular dependency as far as Riverpod's provider graph is concerned
  /// (confirmed via `CircularDependencyError`, not just a style call) —
  /// the reconciliation has to live in a consumer instead, and
  /// LiveBroadcastScreen is the one place that genuinely needs
  /// [cloudStatusProvider] anyway.
  ///
  /// This is what makes the poll ground truth rather than just display
  /// data: [goLive]/[endBroadcast] only cover umpire-initiated
  /// transitions, but the cloud session can also die on its own (FFmpeg
  /// exhausts its reconnect retries, the worker container restarts) with
  /// nothing else telling the phone.
  void reportEndedUnexpectedly() {
    if (!state.isLive) return;
    ++_operation;
    _stopping = true;
    _ticker?.cancel();
    state = BroadcastSessionState(
      elapsed: state.elapsed,
      error: 'Broadcast ended unexpectedly.',
    );
    unawaited(_stopAfterCloudFailure());
  }

  Future<void> _stopAfterCloudFailure() async {
    try {
      await ref.read(hatConnectionServiceProvider).stopStream();
    } catch (_) {
      if (!_disposed) {
        state = BroadcastSessionState(
          elapsed: state.elapsed,
          error:
              'Broadcast ended unexpectedly. Could not confirm the hat stopped; '
              'reconnect or power it off.',
        );
      }
    } finally {
      _stopping = false;
    }
  }
}

final broadcastSessionProvider =
    NotifierProvider<BroadcastSessionNotifier, BroadcastSessionState>(
      BroadcastSessionNotifier.new,
    );

/// Polls the cloud worker every 2s for the active session's real status,
/// once one exists. Built on [Stream.periodic] rather than a hand-rolled
/// `async*` loop with `Future.delayed` — periodic's underlying Timer is
/// tied to the stream subscription and is cancelled automatically when
/// Riverpod disposes this provider; a manual delay loop keeps firing after
/// disposal since nothing ties its Timer to the subscription's lifetime.
final cloudStatusProvider = StreamProvider<CloudStatus>((ref) {
  final sessionId = ref.watch(
    broadcastSessionProvider.select((s) => s.sessionId),
  );
  if (sessionId == null) return const Stream<CloudStatus>.empty();

  final cloud = ref.watch(cloudControlApiClientProvider);
  final sessionStore = ref.watch(userSessionStoreProvider);

  return Stream<void>.periodic(const Duration(seconds: 2)).asyncMap((_) async {
    final token = await sessionStore.readToken();
    if (token == null) {
      throw StateError('Not signed in');
    }
    return cloud.fetchSessionStatus(token, sessionId);
  });
});
