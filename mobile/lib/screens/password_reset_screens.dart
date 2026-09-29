import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';

/// Code-entry view for a recovery challenge issued by the backend.
/// Callbacks must be supplied by the recovery integration; this screen
/// never invents a challenge or treats an arbitrary code as verified.
class PasswordResetCodeScreen extends StatefulWidget {
  const PasswordResetCodeScreen({
    super.key,
    required this.email,
    required this.onVerify,
    required this.onResend,
    this.title = 'Reset your password',
    this.description = 'Enter the 6-digit code we’ve sent to',
    this.verifyLabel = 'Verify code',
    this.alternateLabel,
    this.onAlternate,
    this.developmentCode,
    this.alwaysShowVerifyButton = false,
  });

  final String email;
  final Future<void> Function(String code) onVerify;
  final Future<void> Function() onResend;
  final String title;
  final String description;
  final String verifyLabel;
  final String? alternateLabel;
  final VoidCallback? onAlternate;
  final String? developmentCode;
  final bool alwaysShowVerifyButton;

  @override
  State<PasswordResetCodeScreen> createState() =>
      _PasswordResetCodeScreenState();
}

class _PasswordResetCodeScreenState extends State<PasswordResetCodeScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  Timer? _timer;
  int _seconds = 30;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    _seconds = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _seconds--);
      if (_seconds == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _updateCode(int index, String value) {
    if (value.length > 1) {
      // SMS autofill and paste can supply the complete code in one field.
      final start = value.length == 6 ? 0 : index;
      for (
        var offset = 0;
        offset < value.length && start + offset < 6;
        offset++
      ) {
        _controllers[start + offset].text = value[offset];
      }
      _focusNodes[(start + value.length).clamp(0, 5)].requestFocus();
    } else if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _error = null);
  }

  Future<void> _verify() async {
    final code = _controllers.map((controller) => controller.text).join();
    if (code.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onVerify(code);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We could not verify that code. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || _seconds > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onResend();
      if (mounted) setState(_startCountdown);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We could not resend the code. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _RecoveryIcon(Icons.mail_outline),
        const SizedBox(height: 24),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
        ),
        const SizedBox(height: 12),
        Text(
          widget.description,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: const Color(0xFF6B7A9C)),
        ),
        Text(
          widget.email,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 32),
        if (widget.developmentCode != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Development code: ${widget.developmentCode}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
        ],
        AutofillGroup(
          child: Row(
            children: List.generate(
              6,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 5 ? 0 : 10),
                  child: TextField(
                    key: Key('resetCode$index'),
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    autofillHints: index == 0
                        ? const [AutofillHints.oneTimeCode]
                        : null,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      semanticCounterText: 'Digit ${index + 1} of 6',
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (value) => _updateCode(index, value),
                    onSubmitted: (_) => _verify(),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Didn’t receive a code?'),
            TextButton(
              onPressed: _seconds == 0 && !_busy ? _resend : null,
              child: Text(
                _seconds == 0
                    ? 'Resend'
                    : 'Resend in 00:${_seconds.toString().padLeft(2, '0')}',
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          Text(
            _error!,
            style: const TextStyle(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
        if (widget.alwaysShowVerifyButton ||
            _controllers.every((controller) => controller.text.length == 1))
          FilledButton(
            onPressed:
                !_busy &&
                    _controllers.every(
                      (controller) => controller.text.length == 1,
                    )
                ? _verify
                : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : AuthButtonLabel(widget.verifyLabel),
          ),
        if (widget.alternateLabel != null)
          TextButton(
            onPressed: _busy ? null : widget.onAlternate,
            child: Text(widget.alternateLabel!),
          ),
      ],
    ),
  );
}

/// Success view to show only after the backend confirms a password change.
class PasswordResetSuccessScreen extends StatelessWidget {
  const PasswordResetSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) => AuthScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const _RecoveryIcon(Icons.check_rounded),
        const SizedBox(height: 24),
        Text(
          'Password updated',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
        ),
        const SizedBox(height: 12),
        Text(
          'Your password has been changed\nsuccessfully.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: const Color(0xFF6B7A9C)),
        ),
        const SizedBox(height: 48),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/login', (_) => false),
          child: const AuthButtonLabel('Back to Sign In'),
        ),
      ],
    ),
  );
}

class _RecoveryIcon extends StatelessWidget {
  const _RecoveryIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 104,
      height: 104,
      decoration: const BoxDecoration(
        color: Color(0xFFEEF7FF),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0xFFE0F0FF),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF0085FF), size: 44),
        ),
      ),
    ),
  );
}
