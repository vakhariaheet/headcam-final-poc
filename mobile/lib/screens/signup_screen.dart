import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/user_auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import 'signup_flow_screens.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _acceptedTerms = false;
  bool _showTermsError = false;

  bool get _hasLength => _passwordController.text.length >= 8;
  bool get _hasNumber => RegExp(r'\d').hasMatch(_passwordController.text);
  bool get _hasLetter => RegExp(r'[A-Za-z]').hasMatch(_passwordController.text);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _showTermsError = !_acceptedTerms);
    if (!valid || !_acceptedTerms) return;

    final nameParts = _nameController.text.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1
        ? nameParts.sublist(1).join(' ')
        : null;
    final ok = await ref
        .read(userAuthProvider.notifier)
        .signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: firstName,
          lastName: lastName,
        );
    if (!ok || !mounted) return;

    final challenge = ref.read(userAuthProvider).signupChallenge;
    if (challenge == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SignupVerificationScreen(initialChallenge: challenge),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(userAuthProvider);
    final isLoading = auth.status == UserAuthStatus.loading;

    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthHeading(
                title: 'Create your account',
                subtitle: 'Get started with CreasePoint and bring a new perspective to cricket.',
              ),
              TextFormField(
                key: const Key('signupNameField'),
                controller: _nameController,
                enabled: !isLoading,
                autofillHints: const [AutofillHints.name],
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your full name'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('signupEmailField'),
                controller: _emailController,
                enabled: !isLoading,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
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
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('signupPasswordField'),
                controller: _passwordController,
                enabled: !isLoading,
                autofillHints: const [AutofillHints.newPassword],
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) =>
                    value == null ||
                        value.length < 8 ||
                        !RegExp(r'[A-Za-z]').hasMatch(value) ||
                        !RegExp(r'\d').hasMatch(value)
                    ? 'Use 8+ characters with a letter and number'
                    : null,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _PasswordRule(
                    label: 'At least 8 characters',
                    passed: _hasLength,
                  ),
                  _PasswordRule(label: '1 number', passed: _hasNumber),
                  _PasswordRule(label: '1 letter', passed: _hasLetter),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acceptedTerms,
                    onChanged: isLoading
                        ? null
                        : (value) => setState(() {
                            _acceptedTerms = value ?? false;
                            _showTermsError = false;
                          }),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 11),
                      child: GestureDetector(
                        onTap: _showLegalUnavailable,
                        child: const Text.rich(
                          TextSpan(
                            text: 'I agree to the ',
                            children: [
                              TextSpan(
                                text: 'Terms of Service',
                                style: TextStyle(color: AppColors.blue500),
                              ),
                              TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: TextStyle(color: AppColors.blue500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_showTermsError)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    'Accept the Terms of Service and Privacy Policy',
                    style: TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              if (auth.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  auth.error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const AuthButtonLabel('Create Account'),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text('OR'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 10),
              _SignupSocialButton(
                label: 'Continue with Google',
                icon: const Text(
                  'G',
                  style: TextStyle(
                    color: Color(0xFF4285F4),
                    fontWeight: FontWeight.w800,
                    fontSize: 23,
                  ),
                ),
                onPressed: isLoading
                    ? null
                    : () => _showSocialUnavailable('Google'),
              ),
              const SizedBox(height: 8),
              _SignupSocialButton(
                label: 'Continue with Apple',
                icon: const Icon(Icons.apple, color: Colors.black, size: 26),
                onPressed: isLoading
                    ? null
                    : () => _showSocialUnavailable('Apple'),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Already have an account?'),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () =>
                              Navigator.of(context)
                                  .pushReplacementNamed('/login'),
                    child: const Text('Sign In'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSocialUnavailable(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$provider sign-up is not available yet. Please create your account with email.',
        ),
      ),
    );
  }

  void _showLegalUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This legal document is not published yet.'),
      ),
    );
  }
}

class _PasswordRule extends StatelessWidget {
  const _PasswordRule({required this.label, required this.passed});

  final String label;
  final bool passed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        passed ? Icons.check_circle : Icons.circle_outlined,
        size: 14,
        color: passed ? AppColors.success : AppColors.textSecondary,
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _SignupSocialButton extends StatelessWidget {
  const _SignupSocialButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.textPrimary,
      minimumSize: const Size.fromHeight(48),
      side: const BorderSide(color: Color(0xFFD8E5F3), width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    onPressed: onPressed,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
