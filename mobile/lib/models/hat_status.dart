/// Camera health the hat reports in its `INFO` reply.
enum HatCameraHealth {
  /// No camera failures since the last healthy run.
  ok,

  /// The camera failed and the hat restarted itself; it is running again.
  recovered,

  /// The hat gave up after its automatic restarts. It needs a power cycle.
  failed,
}

/// The connected hat's identity, firmware, and camera health, from the
/// owner-only `{"cmd":"INFO"}` command.
class HatInfo {
  const HatInfo({
    required this.serialNumber,
    required this.hardwareModel,
    required this.firmwareVersion,
    this.camera = HatCameraHealth.ok,
    this.cameraRestarts = 0,
    this.cameraMaxRestarts = 3,
  });

  /// Parses an FFE2 `{"event":"info",...}` notification, or returns null
  /// when [json] is not a well-formed reply.
  static HatInfo? fromNotification(Map<String, dynamic> json) {
    if (json['event'] != 'info') return null;
    final id = json['id'];
    final model = json['model'];
    final firmware = json['fw'];
    if (id is! String || model is! String || firmware is! String) return null;
    final restarts = json['camera_restarts'];
    final maxRestarts = json['camera_max'];
    return HatInfo(
      serialNumber: id,
      hardwareModel: model,
      firmwareVersion: firmware,
      camera: switch (json['camera']) {
        'failed' => HatCameraHealth.failed,
        'recovered' => HatCameraHealth.recovered,
        _ => HatCameraHealth.ok,
      },
      cameraRestarts: restarts is int ? restarts : 0,
      cameraMaxRestarts: maxRestarts is int ? maxRestarts : 3,
    );
  }

  /// The hat's Bluetooth address (`AABBCCDDEEFF`); stable across phones,
  /// unlike the platform's BLE device id.
  final String serialNumber;
  final String hardwareModel;
  final String firmwareVersion;
  final HatCameraHealth camera;

  /// Automatic restarts in the current failure streak.
  final int cameraRestarts;
  final int cameraMaxRestarts;
}

/// A camera failure, notified live as `{"event":"camera_fault",...}`.
class HatCameraFault {
  const HatCameraFault({
    required this.reason,
    required this.restarting,
    required this.restarts,
    required this.maxRestarts,
  });

  static HatCameraFault? fromNotification(Map<String, dynamic> json) {
    if (json['event'] != 'camera_fault') return null;
    final reason = json['reason'];
    final action = json['action'];
    final restarts = json['restarts'];
    final maxRestarts = json['max'];
    if (reason is! String ||
        (action != 'restarting' && action != 'stopped') ||
        restarts is! int ||
        maxRestarts is! int) {
      return null;
    }
    return HatCameraFault(
      reason: reason,
      restarting: action == 'restarting',
      restarts: restarts,
      maxRestarts: maxRestarts,
    );
  }

  /// Firmware code: `video_start_failed`, `video_no_frames`, `video_stalled`.
  final String reason;

  /// True when the hat is rebooting to retry; false when it has given up.
  final bool restarting;

  /// This restart's number (1-based) when [restarting].
  final int restarts;
  final int maxRestarts;
}

/// Progress of a firmware update, notified as `{"event":"ota",...}`.
sealed class HatUpdateEvent {
  const HatUpdateEvent();

  static HatUpdateEvent? fromNotification(Map<String, dynamic> json) {
    if (json['event'] != 'ota') return null;
    switch (json['status']) {
      case 'started':
        return const HatUpdateStarted();
      case 'downloading':
        final progress = json['progress'];
        return progress is int ? HatUpdateDownloading(progress) : null;
      case 'rebooting':
        final version = json['version'];
        return HatUpdateRebooting(version is String ? version : null);
      case 'error':
        final reason = json['reason'];
        return HatUpdateFailed(reason is String ? reason : 'unknown_error');
    }
    return null;
  }
}

class HatUpdateStarted extends HatUpdateEvent {
  const HatUpdateStarted();
}

class HatUpdateDownloading extends HatUpdateEvent {
  const HatUpdateDownloading(this.percent);
  final int percent;
}

/// The image verified; the hat is restarting into it.
class HatUpdateRebooting extends HatUpdateEvent {
  const HatUpdateRebooting(this.version);
  final String? version;
}

class HatUpdateFailed extends HatUpdateEvent {
  const HatUpdateFailed(this.reason);

  /// Firmware code, e.g. `no_wifi`, `streaming`, `hash_mismatch`.
  final String reason;
}

/// A published firmware build, from `GET /api/v1/firmware-releases`.
class FirmwareRelease {
  const FirmwareRelease({
    required this.version,
    required this.sha256,
    required this.sizeBytes,
    required this.downloadUrl,
    this.notes,
  });

  factory FirmwareRelease.fromJson(Map<String, dynamic> json) =>
      FirmwareRelease(
        version: json['version'] as String,
        sha256: json['sha256'] as String,
        sizeBytes: json['sizeBytes'] as int,
        downloadUrl: json['downloadUrl'] as String,
        notes: json['notes'] as String?,
      );

  final String version;
  final String sha256;
  final int sizeBytes;

  /// Plain-HTTP address the hat downloads from itself.
  final String downloadUrl;
  final String? notes;
}

/// Orders dotted release names numerically (`0.10.0` > `0.9.2`). Parts that
/// are not numbers compare as text; a pre-release suffix (`1.0.0-rc1`) sorts
/// before the plain release.
int compareFirmwareVersions(String a, String b) {
  List<String> core(String v) => v.split(RegExp('[-+]')).first.split('.');
  final left = core(a);
  final right = core(b);
  for (var i = 0; i < left.length || i < right.length; i++) {
    final l = i < left.length ? left[i] : '0';
    final r = i < right.length ? right[i] : '0';
    final ln = int.tryParse(l);
    final rn = int.tryParse(r);
    final order = ln != null && rn != null ? ln.compareTo(rn) : l.compareTo(r);
    if (order != 0) return order;
  }
  final leftPre = _preRelease(a);
  final rightPre = _preRelease(b);
  if (leftPre == null || rightPre == null) {
    if (leftPre == rightPre) return 0;
    return leftPre != null ? -1 : 1;
  }
  return leftPre.compareTo(rightPre);
}

/// `rc1` in `1.0.0-rc1+build`; null for a plain release. Build metadata
/// after `+` does not affect ordering.
String? _preRelease(String version) {
  final withoutBuild = version.split('+').first;
  final dash = withoutBuild.indexOf('-');
  return dash < 0 ? null : withoutBuild.substring(dash + 1);
}
