import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/user_auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_header.dart';

/// Initial route: validates any stored session against the backend and
/// skips straight past login if it's still good, otherwise sends the
/// umpire to the welcome screen. Shows a branded splash while deciding.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(userAuthProvider.notifier).restoreSession(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UserAuthState>(userAuthProvider, (previous, next) {
      if (next.status == UserAuthStatus.authenticated) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else if (next.status == UserAuthStatus.unauthenticated) {
        Navigator.of(context).pushReplacementNamed('/welcome');
      }
    });

    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: BrandHeader()),
    );
  }
}
