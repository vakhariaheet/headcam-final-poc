import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

class PreflightState {
  const PreflightState({
    this.tiltDegrees = 0,
    this.audioLevel = 0,
    this.uplinkMbps = 0,
    this.checking = false,
  });

  final double tiltDegrees;
  final double audioLevel; // 0..1
  final double uplinkMbps;
  final bool checking;

  bool get tiltOk => tiltDegrees.abs() < 10;
  bool get uplinkOk => uplinkMbps >= 2.0;
  bool get passed => checking && tiltOk && uplinkOk;

  PreflightState copyWith({
    double? tiltDegrees,
    double? audioLevel,
    double? uplinkMbps,
    bool? checking,
  }) => PreflightState(
    tiltDegrees: tiltDegrees ?? this.tiltDegrees,
    audioLevel: audioLevel ?? this.audioLevel,
    uplinkMbps: uplinkMbps ?? this.uplinkMbps,
    checking: checking ?? this.checking,
  );
}

/// Screen 5's 3-second pre-flight check (spec §6.2): hard-blocks broadcast
/// start on >10° tilt or <2.0 Mbps uplink. Tilt comes from the phone's real
/// accelerometer; audio level and uplink speed are simulated since there's
/// no real mic level or bandwidth probe wired up yet.
class PreflightNotifier extends Notifier<PreflightState> {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _mockTimer;
  final _random = Random();

  @override
  PreflightState build() {
    ref.onDispose(() {
      _accelSub?.cancel();
      _mockTimer?.cancel();
    });
    return const PreflightState();
  }

  void start() {
    state = state.copyWith(checking: true);

    // Real device accelerometer. Note: the iOS Simulator reports a static,
    // near-flat reading rather than a live tilt, so the ">10°" failure path
    // won't visibly trigger there — the sensor integration itself is real.
    _accelSub = accelerometerEventStream().listen((event) {
      final pitch = atan2(event.y, event.z) * 180 / pi;
      state = state.copyWith(tiltDegrees: pitch);
    });

    _mockTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      state = state.copyWith(
        audioLevel: 0.2 + _random.nextDouble() * 0.5,
        uplinkMbps: 3.5 + _random.nextDouble() * 2,
      );
    });
  }

  void stop() {
    _accelSub?.cancel();
    _mockTimer?.cancel();
    _accelSub = null;
    _mockTimer = null;
    // Deferred: stop() can run from a screen's dispose() during widget-tree
    // finalization (e.g. navigating away right after an awaited call), and
    // Riverpod disallows a synchronous state write at that point — this
    // defers it to the next microtask instead, per Riverpod's own guidance.
    // scheduleMicrotask, not Future(...) — the Future(...) constructor
    // schedules via a zero-duration Timer, not a true microtask, which a
    // widget test's "no pending timers" check catches at teardown.
    scheduleMicrotask(() {
      state = state.copyWith(checking: false);
    });
  }
}

final preflightProvider = NotifierProvider<PreflightNotifier, PreflightState>(
  PreflightNotifier.new,
);
