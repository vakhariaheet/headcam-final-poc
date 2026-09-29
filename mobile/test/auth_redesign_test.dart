import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/login_screen.dart';
import 'package:mobile/screens/password_reset_screens.dart';
import 'package:mobile/screens/signup_screen.dart';
import 'package:mobile/screens/welcome_screen.dart';
import 'package:mobile/models/app_user.dart';
import 'package:mobile/services/auth_api_client.dart';
import 'package:mobile/state/user_auth_provider.dart';

class _SuccessfulAuth extends UserAuthNotifier {
  @override
  UserAuthState build() =>
      const UserAuthState(status: UserAuthStatus.unauthenticated);

  @override
  Future<bool> logIn({required String email, required String password}) async =>
      true;
}

class _SignupAuth extends UserAuthNotifier {
  static const challenge = SignupChallenge(
    verificationToken: 'verification-token',
    email: 'umpire@example.com',
    expiresInSeconds: 600,
    developmentCode: '123456',
  );

  var signupCalls = 0;

  @override
  UserAuthState build() =>
      const UserAuthState(status: UserAuthStatus.unauthenticated);

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    String? lastName,
  }) async {
    signupCalls++;
    state = const UserAuthState(
      status: UserAuthStatus.awaitingVerification,
      signupChallenge: challenge,
    );
    return true;
  }

  @override
  Future<bool> verifySignupEmail(String code) async {
    if (code != '123456') return false;
    state = const UserAuthState(
      status: UserAuthStatus.authenticated,
      currentUser: AppUser(
        id: 'user-1',
        email: 'umpire@example.com',
        firstName: 'Test',
        lastName: 'Umpire',
        role: 'UMPIRE',
      ),
    );
    return true;
  }

  @override
  Future<bool> resendSignupVerification() async => true;
}

void main() {
  testWidgets('signup requires terms before it starts account creation', (
    tester,
  ) async {
    final notifier = _SignupAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userAuthProvider.overrideWith(() => notifier)],
        child: const MaterialApp(home: SignupScreen()),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('signupNameField')),
      'Test Umpire',
    );
    await tester.enterText(
      find.byKey(const Key('signupEmailField')),
      'umpire@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signupPasswordField')),
      'password1',
    );
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pump();
    expect(
      find.text('Accept the Terms of Service and Privacy Policy'),
      findsOneWidget,
    );
    expect(notifier.signupCalls, 0);
  });

  testWidgets('signup advances through verification and first-hat setup', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userAuthProvider.overrideWith(_SignupAuth.new)],
        child: MaterialApp(
          home: const SignupScreen(),
          routes: {
            '/home': (_) => const Scaffold(body: Text('Signed-in Home')),
            '/discovery': (_) => const Scaffold(body: Text('Hat discovery')),
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('signupNameField')),
      'Test Umpire',
    );
    await tester.enterText(
      find.byKey(const Key('signupEmailField')),
      'umpire@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signupPasswordField')),
      'password1',
    );
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('Development code: 123456'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('resetCode0')), '123456');
    await tester.pump();
    await tester.ensureVisible(find.text('Verify Email'));
    await tester.tap(find.text('Verify Email'));
    await tester.pumpAndSettle();
    expect(find.text('Account created!'), findsOneWidget);
    expect(find.byKey(const Key('accountCreatedConfetti')), findsOneWidget);

    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Set up your first\nUmpireHat'), findsOneWidget);
    await tester.ensureVisible(find.text('Maybe later'));
    await tester.tap(find.text('Maybe later'));
    await tester.pumpAndSettle();
    expect(find.text('Signed-in Home'), findsOneWidget);
  });

  testWidgets('successful login opens Home and clears the auth stack', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userAuthProvider.overrideWith(_SuccessfulAuth.new)],
        child: MaterialApp(
          home: const LoginScreen(),
          routes: {
            '/home': (_) => const Scaffold(body: Text('Signed-in Home')),
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('loginEmailField')),
      'umpire@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('loginPasswordField')),
      'password123',
    );
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Signed-in Home'), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.text('Signed-in Home'))).canPop(),
      isFalse,
    );
  });

  testWidgets('create-account action is visible without scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [userAuthProvider.overrideWith(_SuccessfulAuth.new)],
        child: MaterialApp(
          home: const LoginScreen(),
          routes: {
            '/signup': (_) => const Scaffold(body: Text('Signup destination')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.text('Create an account');
    expect(action, findsOneWidget);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(844));

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Signup destination'), findsOneWidget);
  });

  testWidgets('welcome fits a small phone and opens signup', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: const WelcomeScreen(),
        routes: {
          '/signup': (_) => const Scaffold(body: Text('Signup destination')),
        },
      ),
    );
    await tester.ensureVisible(find.text('Get Started'));
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Signup destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'code paste fills six digits and verification uses the callback',
    (tester) async {
      String? verified;
      await tester.pumpWidget(
        MaterialApp(
          home: PasswordResetCodeScreen(
            email: 'umpire@example.com',
            onVerify: (code) async {
              verified = code;
            },
            onResend: () async {},
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('resetCode0')), '123456');
      await tester.pump();
      await tester.ensureVisible(find.text('Verify code'));
      await tester.tap(find.text('Verify code'));
      await tester.pump();
      expect(verified, '123456');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('resend is blocked for thirty seconds and then calls delivery', (
    tester,
  ) async {
    var resent = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordResetCodeScreen(
          email: 'umpire@example.com',
          onVerify: (_) async {},
          onResend: () async {
            resent++;
          },
        ),
      ),
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Resend in 00:30'),
          )
          .onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 30));
    await tester.ensureVisible(find.text('Resend'));
    await tester.tap(find.text('Resend'));
    await tester.pump();
    expect(resent, 1);
    expect(find.text('Resend in 00:30'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
