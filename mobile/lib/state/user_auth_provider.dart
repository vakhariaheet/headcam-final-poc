import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../services/app_logger.dart';
import '../services/auth_api_client.dart';
import '../services/user_session_store.dart';

enum UserAuthStatus {
  unknown,
  loading,
  awaitingVerification,
  authenticated,
  unauthenticated,
}

class UserAuthState {
  const UserAuthState({
    this.status = UserAuthStatus.unknown,
    this.currentUser,
    this.signupChallenge,
    this.error,
  });

  final UserAuthStatus status;
  final AppUser? currentUser;
  final SignupChallenge? signupChallenge;
  final String? error;
}

/// Override at build/run time with `--dart-define=BACKEND_BASE_URL=...` —
/// e.g. a Cloudflare quick-tunnel URL when testing against a physical
/// device that can't reach the host machine's `localhost` directly.
const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

final authApiClientProvider = Provider<AuthApiClient>(
  (ref) => AuthApiClient(baseUrl: _backendBaseUrl.isEmpty ? null : _backendBaseUrl),
);
final userSessionStoreProvider = Provider<UserSessionStore>(
  (ref) => UserSessionStore(),
);

/// Real UmpireHat account auth, backed by backend/'s API — distinct from
/// the mocked broadcast-channel OAuth in broadcast_channels_provider.dart.
class UserAuthNotifier extends Notifier<UserAuthState> {
  late final AuthApiClient _api = ref.read(authApiClientProvider);
  late final UserSessionStore _sessionStore = ref.read(
    userSessionStoreProvider,
  );

  @override
  UserAuthState build() => const UserAuthState();

  /// Checks for a stored session on app start and validates it against the
  /// backend, so a signed-in umpire skips straight past the login screen.
  Future<void> restoreSession() async {
    state = const UserAuthState(status: UserAuthStatus.loading);
    try {
      // A stuck platform channel (Keychain/Keystore access blocked, or no
      // plugin binding at all) must not strand the app on the splash
      // screen forever — treat a timeout the same as "no session".
      final token = await _sessionStore.readToken().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      if (token == null) {
        state = const UserAuthState(status: UserAuthStatus.unauthenticated);
        return;
      }
      final user = await _api.fetchMe(token);
      state = UserAuthState(
        status: UserAuthStatus.authenticated,
        currentUser: user,
      );
    } catch (e) {
      // Covers both an invalid/expired session and the secure-storage read
      // itself failing — either way, fall back to showing the login screen
      // rather than crashing on startup. Logged at debug, not warning: an
      // expired/missing session on a cold start is the normal signed-out
      // path, not something worth flagging.
      AppLogger.debug(
        'restoreSession failed, falling back to unauthenticated: $e',
        name: 'UserAuthNotifier',
      );
      await _sessionStore.clear().catchError((_) {});
      state = const UserAuthState(status: UserAuthStatus.unauthenticated);
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    String? lastName,
  }) async {
    state = const UserAuthState(status: UserAuthStatus.loading);
    try {
      final challenge = await _api.signUp(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      );
      state = UserAuthState(
        status: UserAuthStatus.awaitingVerification,
        signupChallenge: challenge,
      );
      return true;
    } on AuthApiException catch (e) {
      state = UserAuthState(
        status: UserAuthStatus.unauthenticated,
        error: e.message,
      );
      return false;
    }
  }

  Future<bool> verifySignupEmail(String code) async {
    final challenge = state.signupChallenge;
    if (challenge == null) return false;
    state = UserAuthState(
      status: UserAuthStatus.loading,
      signupChallenge: challenge,
    );
    try {
      final result = await _api.verifyEmail(
        verificationToken: challenge.verificationToken,
        code: code,
      );
      await _sessionStore.saveToken(result.token);
      state = UserAuthState(
        status: UserAuthStatus.authenticated,
        currentUser: result.user,
      );
      return true;
    } on AuthApiException catch (e) {
      state = UserAuthState(
        status: UserAuthStatus.awaitingVerification,
        signupChallenge: challenge,
        error: e.message,
      );
      return false;
    }
  }

  Future<bool> resendSignupVerification() async {
    final challenge = state.signupChallenge;
    if (challenge == null) return false;
    try {
      final replacement = await _api.resendVerification(
        challenge.verificationToken,
      );
      state = UserAuthState(
        status: UserAuthStatus.awaitingVerification,
        signupChallenge: replacement,
      );
      return true;
    } on AuthApiException catch (e) {
      state = UserAuthState(
        status: UserAuthStatus.awaitingVerification,
        signupChallenge: challenge,
        error: e.message,
      );
      return false;
    }
  }

  Future<bool> logIn({required String email, required String password}) {
    return _authenticate(() => _api.logIn(email: email, password: password));
  }

  Future<bool> _authenticate(Future<AuthResult> Function() action) async {
    state = const UserAuthState(status: UserAuthStatus.loading);
    try {
      final result = await action();
      await _sessionStore.saveToken(result.token);
      state = UserAuthState(
        status: UserAuthStatus.authenticated,
        currentUser: result.user,
      );
      return true;
    } on AuthApiException catch (e) {
      state = UserAuthState(
        status: UserAuthStatus.unauthenticated,
        error: e.message,
      );
      return false;
    }
  }

  Future<void> logOut() async {
    await _sessionStore.clear();
    state = const UserAuthState(status: UserAuthStatus.unauthenticated);
  }
}

final userAuthProvider = NotifierProvider<UserAuthNotifier, UserAuthState>(
  UserAuthNotifier.new,
);
