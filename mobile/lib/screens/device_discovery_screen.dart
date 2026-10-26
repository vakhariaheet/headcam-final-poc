import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/hat_device.dart';
import '../state/hat_connection_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/brand_header.dart';
import '../widgets/hat_connection_messages.dart';

const _blue = Color(0xFF0085FF);
const _muted = Color(0xFF6B7A9C);
const _border = Color(0xFFD8E5F3);

/// Entry point for the guided UmpireHat pairing flow.
class DeviceDiscoveryScreen extends StatelessWidget {
  const DeviceDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) => _PairingFrame(
    showProgress: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: BrandHeader(compact: true)),
        const SizedBox(height: 6),
        const _HatImage(height: 210),
        const SizedBox(height: 14),
        Text('Set up your UmpireHat', style: _titleStyle(context)),
        const SizedBox(height: 8),
        Text(
          "Let's connect your device and get you ready to capture the game "
          'from a higher perspective.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: _muted),
        ),
        const SizedBox(height: 20),
        const _FeatureRow(Icons.visibility_outlined, 'Live streaming'),
        const _FeatureRow(Icons.videocam_outlined, 'HD recording'),
        const _FeatureRow(Icons.air, 'Lightweight & comfortable'),
        const _FeatureRow(Icons.settings_outlined, 'Built for the game'),
        const Spacer(),
        FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const _BluetoothPermissionScreen(),
            ),
          ),
          child: const AuthButtonLabel('Add Device'),
        ),
        TextButton(
          onPressed: () => _finishFlow(context),
          child: const Text('Maybe later'),
        ),
      ],
    ),
  );
}

class _BluetoothPermissionScreen extends ConsumerStatefulWidget {
  const _BluetoothPermissionScreen();

  @override
  ConsumerState<_BluetoothPermissionScreen> createState() =>
      _BluetoothPermissionScreenState();
}

class _BluetoothPermissionScreenState
    extends ConsumerState<_BluetoothPermissionScreen> {
  bool _requesting = false;
  String? _error;

  Future<void> _allowBluetooth() async {
    setState(() {
      _requesting = true;
      _error = null;
    });
    final allowed = await ref
        .read(hatConnectionProvider.notifier)
        .requestBluetoothAccess();
    if (!mounted) return;
    if (allowed) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const _ScanningScreen()),
      );
    } else {
      setState(() {
        _requesting = false;
        _error = 'Bluetooth access is needed to find your UmpireHat.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => _PairingFrame(
    activeStep: 0,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading(
          'Enable Bluetooth',
          'We need Bluetooth access to find and connect to your UmpireHat.',
        ),
        const SizedBox(height: 24),
        const _CircleIcon(Icons.bluetooth),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Column(
            children: [
              _InfoRow(
                Icons.security_outlined,
                'We only use Bluetooth to connect your device',
              ),
              _InfoRow(Icons.lock_outline, 'Your data stays private'),
              _InfoRow(
                Icons.settings_outlined,
                'You can change this anytime in settings',
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ],
        const Spacer(),
        FilledButton(
          onPressed: _requesting ? null : _allowBluetooth,
          child: _requesting
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text('Allow Bluetooth'),
        ),
        TextButton(
          onPressed: _requesting ? null : () => _finishFlow(context),
          child: const Text('Not now'),
        ),
      ],
    ),
  );
}

class _ScanningScreen extends ConsumerStatefulWidget {
  const _ScanningScreen();

  @override
  ConsumerState<_ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends ConsumerState<_ScanningScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    Future.microtask(_scan);
  }

  Future<void> _scan() async {
    await Future.wait([
      ref.read(hatConnectionProvider.notifier).startScan(),
      Future<void>.delayed(const Duration(milliseconds: 1500)),
    ]);
    if (!mounted) return;
    final discovered = ref.read(hatConnectionProvider).discovered;
    if (discovered.isEmpty) {
      setState(() => _finished = true);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const _SelectDeviceScreen()),
      );
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PairingFrame(
    activeStep: 0,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading(
          'Searching for devices',
          'Turn on your UmpireHat and keep it nearby. '
              '$hatPairingModeInstruction',
        ),
        const SizedBox(height: 28),
        Center(
          child: SizedBox.square(
            dimension: 250,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (_, _) => CustomPaint(
                painter: _RadarPainter(_animation.value),
                child: const Center(
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: _blue,
                    child: Icon(Icons.bluetooth, color: Colors.white, size: 38),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5FAFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _finished
                  ? const Icon(Icons.search_off, color: _blue, size: 30)
                  : const SizedBox.square(
                      dimension: 30,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _finished
                      ? 'No UmpireHats found. Check the device and try again.'
                      : 'Scanning for UmpireHats...\n'
                            'This may take a few seconds.',
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (_finished)
          FilledButton(
            onPressed: () {
              setState(() => _finished = false);
              _scan();
            },
            child: const Text('Scan Again'),
          ),
      ],
    ),
  );
}

class _SelectDeviceScreen extends ConsumerStatefulWidget {
  const _SelectDeviceScreen();

  @override
  ConsumerState<_SelectDeviceScreen> createState() =>
      _SelectDeviceScreenState();
}

class _SelectDeviceScreenState extends ConsumerState<_SelectDeviceScreen> {
  String? _selectedId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final devices = ref.read(hatConnectionProvider).discovered;
    if (_selectedId == null && devices.isNotEmpty) {
      _selectedId = devices.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(hatConnectionProvider).discovered;
    HatDevice? selected;
    for (final device in devices) {
      if (device.id == _selectedId) selected = device;
    }
    return _PairingFrame(
      activeStep: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading(
            'Select your device',
            'Choose your UmpireHat from the list below.',
          ),
          const SizedBox(height: 18),
          ...devices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeviceOption(
                device: device,
                selected: device.id == _selectedId,
                onTap: () => setState(() => _selectedId = device.id),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const _ScanningScreen()),
            ),
            child: const Text("Can't find your device?"),
          ),
          const Spacer(),
          FilledButton(
            key: const Key('pairingConnectButton'),
            onPressed: selected == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ConnectingScreen(device: selected!),
                    ),
                  ),
            child: const AuthButtonLabel('Connect'),
          ),
        ],
      ),
    );
  }
}

class _ConnectingScreen extends ConsumerStatefulWidget {
  const _ConnectingScreen({required this.device});

  final HatDevice device;

  @override
  ConsumerState<_ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends ConsumerState<_ConnectingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  int _stage = 0;
  bool _failed = false;
  String? _failureMessage;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    Future.microtask(_connect);
  }

  Future<void> _connect() async {
    setState(() {
      _stage = 0;
      _failed = false;
    });
    final connect = ref
        .read(hatConnectionProvider.notifier)
        .connect(widget.device);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _stage = 1);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _stage = 2);
    await connect;
    if (!mounted) return;
    final status = ref.read(hatConnectionProvider).status;
    if (status != HatConnectionStatus.connected) {
      setState(() {
        _failed = true;
        _failureMessage = hatConnectionFailureMessage(status);
      });
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _stage = 3);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const _PairingSuccessScreen()),
    );
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  _StepState _stateFor(int index) {
    if (_failed && index == _stage) return _StepState.failed;
    if (index < _stage) return _StepState.complete;
    if (index == _stage) return _StepState.active;
    return _StepState.pending;
  }

  @override
  Widget build(BuildContext context) => _PairingFrame(
    activeStep: 1,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          _failed ? 'Connection failed' : 'Connecting...',
          _failed
              ? _failureMessage ??
                    'We could not connect to your UmpireHat. Make sure it is '
                        'nearby and try again.'
              : 'Please wait while we pair with your UmpireHat.',
        ),
        const SizedBox(height: 20),
        Center(
          child: SizedBox.square(
            dimension: 230,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (_, child) => CustomPaint(
                painter: _ConnectionRingPainter(
                  _failed ? 0 : _animation.value,
                  _failed,
                ),
                child: child,
              ),
              child: const Padding(
                padding: EdgeInsets.all(28),
                child: _HatImage(height: 160),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _ConnectionStep('Initializing connection', _stateFor(0)),
        _ConnectionStep('Pairing with device...', _stateFor(1)),
        _ConnectionStep('Verifying ownership', _stateFor(2)),
        _ConnectionStep('Finalizing setup', _stateFor(3)),
        const Spacer(),
        if (_failed)
          FilledButton(onPressed: _connect, child: const Text('Try Again')),
      ],
    ),
  );
}

class _PairingSuccessScreen extends ConsumerWidget {
  const _PairingSuccessScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(hatConnectionProvider).connectedDevice;
    final battery = ref
        .watch(hatTelemetryProvider)
        .valueOrNull
        ?.batteryLevelPct;
    return _PairingFrame(
      activeStep: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading(
            'Device paired!',
            'Your UmpireHat has been successfully connected.',
          ),
          const SizedBox(height: 18),
          const Stack(
            alignment: Alignment.topRight,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(12, 18, 12, 0),
                child: _HatImage(height: 190),
              ),
              _SuccessBadge(),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Color(0xFFF5FAFF),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  Icons.devices_other_outlined,
                  device?.name ?? 'UmpireHat',
                  'Connected',
                ),
                const Divider(height: 24),
                _SummaryRow(
                  Icons.signal_cellular_alt,
                  'Signal strength',
                  _signalLabel(device?.rssi ?? -60),
                ),
                const Divider(height: 24),
                _SummaryRow(
                  Icons.battery_5_bar_outlined,
                  'Battery',
                  battery == null ? 'Not reported' : '$battery%',
                ),
              ],
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => Navigator.of(context).pushNamed('/hotspot'),
            child: const AuthButtonLabel('Next: Wi-Fi Setup'),
          ),
          TextButton(
            onPressed: () => _finishFlow(context),
            child: const Text('Set up later'),
          ),
        ],
      ),
    );
  }
}

class _PairingFrame extends StatelessWidget {
  const _PairingFrame({
    required this.child,
    this.activeStep = 0,
    this.showProgress = true,
  });

  final Widget child;
  final int activeStep;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: Colors.white,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: SvgPicture.asset(
                  'lib/assets/creasepoint-auth-arcs.svg',
                  fit: BoxFit.fitWidth,
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 430,
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 42),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Back',
                                    onPressed: () {
                                      if (Navigator.of(context).canPop()) {
                                        Navigator.of(context).pop();
                                      } else {
                                        _finishFlow(context);
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.arrow_back_ios_new,
                                      size: 21,
                                    ),
                                  ),
                                  if (showProgress) ...[
                                    const SizedBox(width: 18),
                                    Expanded(child: _ProgressSteps(activeStep)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 16),
                              Expanded(child: child),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps(this.activeStep);

  final int activeStep;

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(
      4,
      (index) => Expanded(
        child: Container(
          height: 5,
          margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
          decoration: BoxDecoration(
            color: index <= activeStep ? _blue : const Color(0xFFDCE5F0),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, textAlign: TextAlign.center, style: _titleStyle(context)),
      const SizedBox(height: 7),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: _muted),
      ),
    ],
  );
}

TextStyle? _titleStyle(BuildContext context) =>
    Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6);

class _HatImage extends StatelessWidget {
  const _HatImage({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
    'lib/assets/hat.png',
    height: height,
    fit: BoxFit.contain,
    semanticLabel: 'UmpireHat camera',
  );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 21),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 112,
      height: 112,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF5FF),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _blue, size: 54),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Icon(icon, size: 23),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: _muted),
          ),
        ),
      ],
    ),
  );
}

class _DeviceOption extends StatelessWidget {
  const _DeviceOption({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final HatDevice device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: selected ? _blue : _border,
        width: selected ? 1.5 : 1,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 66,
              height: 48,
              child: Image.asset('lib/assets/hat.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${hatPairingStateLabel(device)} · '
                    'Signal: ${_signalLabel(device.rssi)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? _blue : const Color(0xFFB8C5D8),
            ),
          ],
        ),
      ),
    ),
  );
}

enum _StepState { pending, active, complete, failed }

class _ConnectionStep extends StatelessWidget {
  const _ConnectionStep(this.label, this.state);

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      _StepState.complete => Icons.check_circle,
      _StepState.active => Icons.circle,
      _StepState.failed => Icons.error,
      _StepState.pending => Icons.radio_button_unchecked,
    };
    final color = switch (state) {
      _StepState.complete => AppColors.success,
      _StepState.active => _blue,
      _StepState.failed => AppColors.error,
      _StepState.pending => const Color(0xFFB8C5D8),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: state == _StepState.active
                    ? AppColors.textPrimary
                    : _muted,
                fontWeight: state == _StepState.active ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 62,
    height: 62,
    decoration: BoxDecoration(
      color: AppColors.success,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 5),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 12,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: const Icon(Icons.check, color: Colors.white, size: 36),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 23),
      const SizedBox(width: 13),
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
      Text(
        value,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    final fill = Paint()..style = PaintingStyle.fill;
    for (var i = 3; i >= 1; i--) {
      fill.color = _blue.withValues(alpha: 0.045 + i * 0.025);
      canvas.drawCircle(center, maxRadius * i / 3, fill);
    }
    final sweep = Paint()
      ..color = _blue.withValues(alpha: 0.42)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      center,
      center +
          Offset.fromDirection(progress * math.pi * 2 - math.pi / 2, maxRadius),
      sweep,
    );
    final pulseRadius = 36 + (maxRadius - 36) * progress;
    sweep.color = _blue.withValues(alpha: 0.35 * (1 - progress));
    canvas.drawCircle(center, pulseRadius, sweep);
    final dot =
        center + Offset.fromDirection(progress * math.pi * 2, maxRadius * 0.68);
    canvas.drawCircle(dot, 7, Paint()..color = Colors.white);
    canvas.drawCircle(dot, 4.5, Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ConnectionRingPainter extends CustomPainter {
  const _ConnectionRingPainter(this.progress, this.failed);

  final double progress;
  final bool failed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..color = const Color(0xFFDCECF9)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    canvas.drawArc(rect.deflate(8), 0, math.pi * 2, false, base);
    final foreground = Paint()
      ..color = failed ? AppColors.error : _blue
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      rect.deflate(8),
      -math.pi / 2 + progress * math.pi * 2,
      failed ? math.pi * 2 : math.pi * 0.95,
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectionRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.failed != failed;
}

String _signalLabel(int rssi) {
  if (rssi >= -60) return 'Strong';
  if (rssi >= -75) return 'Medium';
  return 'Weak';
}

void _finishFlow(BuildContext context) {
  Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
}
