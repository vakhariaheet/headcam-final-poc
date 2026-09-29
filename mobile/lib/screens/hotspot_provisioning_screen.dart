import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/credential_store_provider.dart';
import '../state/hat_connection_provider.dart';
import '../theme/app_theme.dart';

/// Wi-Fi credentials, the second and final step of pairing (BLE connect +
/// Wi-Fi provisioning — see hat_connection_provider.dart's
/// [HatConnectionNotifier.provisionHotspot]). One action does save +
/// provision + marks the hat as paired, then returns to Home — pairing
/// stays a short, standalone flow, not bundled with starting a broadcast.
class HotspotProvisioningScreen extends ConsumerStatefulWidget {
  const HotspotProvisioningScreen({super.key});

  @override
  ConsumerState<HotspotProvisioningScreen> createState() =>
      _HotspotProvisioningScreenState();
}

class _HotspotProvisioningScreenState
    extends ConsumerState<HotspotProvisioningScreen> {
  final _ssidController = TextEditingController();
  final _passController = TextEditingController();
  String _band = '5GHz';
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final saved = await ref
          .read(secureCredentialStoreProvider)
          .loadHotspotProfile();
      if (saved != null && mounted) {
        _ssidController.text = saved.ssid;
        _passController.text = saved.passphrase;
        setState(() => _band = saved.band);
      }
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _pairHat() async {
    final ssid = _ssidController.text.trim();
    final pass = _passController.text;
    if (ssid.isEmpty || pass.isEmpty) return;

    await ref
        .read(secureCredentialStoreProvider)
        .saveHotspotProfile(ssid: ssid, passphrase: pass, band: _band);

    final success = await ref
        .read(hatConnectionProvider.notifier)
        .provisionHotspot(ssid: ssid, passphrase: pass, band: _band);

    if (success && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Hat paired!')));
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(hatConnectionProvider);
    final isProvisioning =
        connection.status == HatConnectionStatus.provisioning;

    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi Credentials')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'WI-FI CREDENTIALS',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Enter your phone's Personal Hotspot details once — they're "
                'stored in the device Keychain/Keystore and pushed to the hat '
                'over BLE on match day.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _ssidController,
                decoration: const InputDecoration(labelText: 'Hotspot SSID'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _passController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Passphrase',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownMenu<String>(
                initialSelection: _band,
                label: const Text('Band'),
                onSelected: (value) => setState(() => _band = value ?? _band),
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: '5GHz', label: '5 GHz'),
                  DropdownMenuEntry(value: '2.4GHz', label: '2.4 GHz'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (isProvisioning)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Pairing hat...'),
                    ],
                  ),
                ),
              FilledButton(
                onPressed: isProvisioning ? null : _pairHat,
                child: const Text('Pair Hat'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
