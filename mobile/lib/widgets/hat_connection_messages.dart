import '../models/hat_device.dart';
import '../models/hat_status.dart';
import '../state/hat_connection_provider.dart';

/// How to open the hat's pairing window, shown wherever pairing starts.
const hatPairingModeInstruction =
    'Hold the button on your UmpireHat for 3 seconds, then release when both '
    'lights turn on. The blue light double-blinks while it is ready to pair.';

/// Short pairing state for a discovered hat.
String hatPairingStateLabel(HatDevice device) {
  if (device.pairingMode) return 'Ready to pair';
  if (device.owned) return 'Paired to a phone';
  return 'Not in pairing mode';
}

/// User-facing explanation for a connection attempt that did not succeed,
/// or null when [status] is not a failure.
String? hatConnectionFailureMessage(HatConnectionStatus status) =>
    switch (status) {
      HatConnectionStatus.notInPairingMode =>
        'This UmpireHat is not in pairing mode. $hatPairingModeInstruction',
      HatConnectionStatus.ownedByAnother =>
        'This UmpireHat is paired to another phone. To pair it with this '
            'phone instead, put it in pairing mode: $hatPairingModeInstruction',
      HatConnectionStatus.timedOut =>
        'We could not connect to your UmpireHat. Make sure it is nearby and '
            'try again.',
      _ => null,
    };

/// What to tell the user about the hat's camera, preferring a live [fault]
/// over the health the hat reported in [info]. Null when all is well.
String? hatCameraMessage({HatCameraFault? fault, HatInfo? info}) {
  if (fault != null) {
    if (fault.restarting) {
      return 'The camera stopped responding, so your UmpireHat is restarting '
          '(attempt ${fault.restarts} of ${fault.maxRestarts}). Reconnect in '
          'about 30 seconds.';
    }
    return _cameraGaveUp(fault.maxRestarts);
  }
  if (info == null) return null;
  return switch (info.camera) {
    HatCameraHealth.failed => _cameraGaveUp(info.cameraMaxRestarts),
    HatCameraHealth.recovered =>
      'Your UmpireHat restarted ${info.cameraRestarts == 1 ? 'once' : '${info.cameraRestarts} times'} '
          'after a camera problem and is working now. If this keeps '
          'happening, the camera may need service.',
    HatCameraHealth.ok => null,
  };
}

String _cameraGaveUp(int attempts) =>
    'The camera failed $attempts times in a row, so your UmpireHat stopped '
    'retrying. Turn the hat off and on again. If this keeps happening, the '
    'camera may need service.';

/// True when [hatCameraMessage] describes a hat that needs a power cycle.
bool hatCameraNeedsPowerCycle({HatCameraFault? fault, HatInfo? info}) =>
    fault != null ? !fault.restarting : info?.camera == HatCameraHealth.failed;

/// User-facing explanation for a firmware update failure [reason].
String hatUpdateFailureMessage(String reason) => switch (reason) {
  'no_wifi' =>
    'Your UmpireHat is not on Wi-Fi. Connect it to your hotspot, then try '
        'again.',
  'streaming' => 'Stop the broadcast before updating your UmpireHat.',
  'busy' => 'An update is already running on your UmpireHat.',
  'bad_url' ||
  'connect_failed' ||
  'http_status' ||
  'download_failed' ||
  'size_mismatch' =>
    'Your UmpireHat could not download the update. Make sure its Wi-Fi can '
        'reach the CreasePoint server, then try again.',
  'hash_mismatch' =>
    'The downloaded update did not match the published release, so your '
        'UmpireHat kept its current firmware.',
  'older_firmware' =>
    'This release is older than the firmware already on your UmpireHat.',
  'no_progress' || 'ble_disconnected' || 'timeout' =>
    'Lost contact with your UmpireHat during the update. Reconnect to check '
        'its version; an interrupted update leaves the current firmware '
        'running.',
  'check_failed' =>
    'Could not check for updates. Check your connection and try again.',
  'signed_out' => 'Sign in to check for updates.',
  'no_info' =>
    'Reconnect to your UmpireHat to check for updates. Hats on firmware '
        'older than 0.2.0 need a wired update first.',
  _ =>
    'The update did not finish. Your UmpireHat is still running its current '
        'firmware.',
};
