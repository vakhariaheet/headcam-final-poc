import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_api_client.dart';
import '../state/user_auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import 'password_reset_screens.dart';

/// Email challenge issued after the create-account form succeeds.
class SignupVerificationScreen extends ConsumerWidget {
  const SignupVerificationScreen({super.key, required this.initialChallenge});

  final SignupChallenge initialChallenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(userAuthProvider);
    final challenge = auth.signupChallenge ?? initialChallenge;
    return PasswordResetCodeScreen(
      key: ValueKey(challenge.verificationToken),
      email: challenge.email,
      title: 'Verify your email',
      description: 'We’ve sent a 6-digit code to',
      verifyLabel: 'Verify Email',
      alwaysShowVerifyButton: true,
      developmentCode: challenge.developmentCode,
      alternateLabel: 'Use a different email',
      onAlternate: () => Navigator.of(context).pop(),
      onVerify: (code) async {
        final verified = await ref
            .read(userAuthProvider.notifier)
            .verifySignupEmail(code);
        if (!verified) {
          throw StateError(
            ref.read(userAuthProvider).error ?? 'Verification failed',
          );
        }
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => const AccountCreatedScreen(),
            ),
            (_) => false,
          );
        }
      },
      onResend: () async {
        final sent = await ref
            .read(userAuthProvider.notifier)
            .resendSignupVerification();
        if (!sent) {
          throw StateError(ref.read(userAuthProvider).error ?? 'Resend failed');
        }
      },
    );
  }
}

/// Confirmation shown only after the server accepts the verification code.
class AccountCreatedScreen extends StatelessWidget {
  const AccountCreatedScreen({super.key});

  @override
  Widget build(BuildContext context) => AuthScaffold(
    showBackButton: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        const _SuccessBurst(),
        const SizedBox(height: 44),
        Text(
          'Account created!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
        ),
        const SizedBox(height: 10),
        Text(
          'Welcome to CreasePoint.\nYour account has been successfully verified.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: const Color(0xFF6B7A9C)),
        ),
        const SizedBox(height: 64),
        FilledButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => const FirstHatSetupScreen(),
            ),
          ),
          child: const AuthButtonLabel('Continue'),
        ),
      ],
    ),
  );
}

/// First-run handoff from account creation into the existing pairing flow.
class FirstHatSetupScreen extends StatelessWidget {
  const FirstHatSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => AuthScaffold(
    showBackButton: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Set up your first\nUmpireHat',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
        ),
        const SizedBox(height: 18),
        AspectRatio(
          aspectRatio: 3 / 2,
          child: Image.asset(
            'lib/assets/hat.png',
            fit: BoxFit.contain,
            alignment: Alignment.center,
            semanticLabel: 'UmpireHat wearable camera',
          ),
        ),
        const SizedBox(height: 24),
        const _SetupStep(
          icon: Icons.camera_alt_outlined,
          label: 'Pair your UmpireHat',
        ),
        const _SetupStep(icon: Icons.wifi, label: 'Connect to network'),
        const _SetupStep(icon: Icons.podcasts, label: 'Configure streaming'),
        const _SetupStep(
          icon: Icons.smart_display_outlined,
          label: 'Start capturing',
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () {
            final navigator = Navigator.of(context);
            navigator.pushNamedAndRemoveUntil('/home', (_) => false);
            navigator.pushNamed('/discovery');
          },
          child: const AuthButtonLabel("Let's Get Started"),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/home', (_) => false),
          child: const Text('Maybe later'),
        ),
      ],
    ),
  );
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(width: 44, child: Icon(icon, color: AppColors.textPrimary)),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: const Color(0xFF6B7A9C)),
        ),
      ],
    ),
  );
}

class _SuccessBurst extends StatefulWidget {
  const _SuccessBurst();

  @override
  State<_SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<_SuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0.45;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      key: const Key('accountCreatedConfetti'),
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) =>
                    CustomPaint(painter: _ConfettiPainter(_controller.value)),
              ),
            ),
          ),
          Container(
            width: 104,
            height: 104,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF7FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Color(0xFF0085FF),
              size: 56,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.progress);

  final double progress;

  static const _colors = [
    AppColors.blue500,
    AppColors.warning,
    AppColors.error,
    AppColors.success,
    Color(0xFF26B8E6),
    Color(0xFF7A5AF8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final opacity = (1 - Curves.easeIn.transform(progress.clamp(0.0, 1.0)))
        .clamp(0.0, 1.0);

    for (var index = 0; index < 18; index++) {
      final angle = -2.85 + index * 0.335;
      final distance = (28 + (index % 5) * 12) * eased;
      final gravity = 34 * progress * progress;
      final position = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance + gravity,
      );
      final paint = Paint()
        ..color = _colors[index % _colors.length].withValues(alpha: opacity);

      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(angle + progress * (2 + index % 3));
      if (index.isEven) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-4, -2, 8, 4),
            const Radius.circular(1.5),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, 3, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
