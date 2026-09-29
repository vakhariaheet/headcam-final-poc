import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';

/// Recovery entry screen. Code delivery awaits backend email integration.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _requested = false;

  @override
  Widget build(BuildContext context) => AuthScaffold(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
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
                  child: const Icon(
                    Icons.mail_outline,
                    color: Color(0xFF0085FF),
                    size: 42,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Reset your password',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
          ),
          const SizedBox(height: 12),
          Text(
            'Enter the email address associated with your account.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: const Color(0xFF6B7A9C)),
          ),
          const SizedBox(height: 28),
          TextFormField(
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              hintText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) =>
                value == null ||
                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(value.trim())
                ? 'Enter a valid email'
                : null,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                setState(() => _requested = true);
              }
            },
            child: const AuthButtonLabel('Send reset code'),
          ),
          if (_requested) ...[
            const SizedBox(height: 16),
            const Text(
              'Password recovery is not available yet. No code has been sent. Please contact your administrator for help.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Sign In'),
          ),
        ],
      ),
    ),
  );
}
