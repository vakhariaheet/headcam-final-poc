import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'screens/auth_gate.dart';
import 'screens/device_discovery_screen.dart';
import 'screens/hotspot_provisioning_screen.dart';
import 'screens/login_screen.dart';
import 'screens/match_setup_screen.dart';
import 'screens/preflight_check_screen.dart';
import 'screens/select_hat_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'theme/app_theme.dart';

// Temporary hardware-test shortcut. Set SKIP_MATCH_SETUP=false to restore
// match URL and channel selection before preflight.
const _skipMatchSetup = bool.fromEnvironment(
  'SKIP_MATCH_SETUP',
  defaultValue: true,
);

/// A signed-in umpire lands on [AppShell] (Home/Live/Devices/Recordings/
/// Settings). Pairing a hat (Discovery → Hotspot) and starting a broadcast
/// (Match Setup → Preflight) are two separate short flows pushed on top of
/// the shell from Home — neither includes `/live`, which isn't a route at
/// all: going live lands the umpire on the shell's Live tab instead (see
/// preflight_check_screen.dart, shell_navigation_provider.dart). A plain
/// named route table is still enough for these two short pushes, no
/// router package needed.
class CreasePointApp extends StatelessWidget {
  const CreasePointApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CreasePoint',
      theme: buildAppTheme(),
      initialRoute: '/',
      routes: {
        '/': (_) => const AuthGate(),
        '/welcome': (_) => const WelcomeScreen(),
        '/forgot-password': (_) => const ForgotPasswordScreen(),
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/home': (_) => const AppShell(),
        '/discovery': (_) => const DeviceDiscoveryScreen(),
        '/hotspot': (_) => const HotspotProvisioningScreen(),
        '/select-hat': (_) => const SelectHatScreen(),
        '/match-setup': (_) => _skipMatchSetup
            ? const PreflightCheckScreen()
            : const MatchSetupScreen(),
        '/preflight': (_) => const PreflightCheckScreen(),
      },
    );
  }
}
