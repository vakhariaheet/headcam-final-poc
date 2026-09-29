import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/auth_scaffold.dart';

/// Photo-led welcome screen for signed-out users.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: const Color(0xFF071A2A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'lib/assets/splash.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x22071A2A),
                  Colors.transparent,
                  Color(0xEE001015),
                ],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 44, 28, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _WelcomeLogo(),
                          const SizedBox(height: 14),
                          const Text(
                            'A HIGHER PERSPECTIVE\nON CRICKET',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              letterSpacing: 1.8,
                              height: 1.5,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(height: 180),
                          const Text(
                            'Capture.\nStream.\nRelive.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              height: 1.08,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Wearable camera technology\nfor a new perspective on cricket.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0085FF),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () =>
                                Navigator.of(context).pushNamed('/signup'),
                            child: const AuthButtonLabel('Get Started'),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'Already have an account?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pushNamed('/login'),
                                child: const Text('Sign In'),
                              ),
                            ],
                          ),
                        ],
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

/// Transparent vector lockup so the welcome photo shows behind the mark.
class _WelcomeLogo extends StatelessWidget {
  const _WelcomeLogo();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'CreasePoint',
    child: Column(
      children: [
        SvgPicture.string(
          '''<svg viewBox="0 0 140 100" xmlns="http://www.w3.org/2000/svg">
<g fill="white"><rect x="36" y="6" width="12" height="84" rx="6"/><rect x="64" y="6" width="12" height="84" rx="6"/><rect x="92" y="6" width="12" height="84" rx="6"/></g>
<path d="M2 66 Q70 9 138 66 Q70 31 2 66" fill="#0085FF"/>
<circle cx="70" cy="58" r="12" fill="white" stroke="#071A2A" stroke-width="3"/><circle cx="74" cy="54" r="3" fill="#071A2A"/>
</svg>''',
          width: 140,
          height: 100,
        ),
        const SizedBox(height: 4),
        const Text(
          'CREASEPOINT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 3.5,
          ),
        ),
      ],
    ),
  );
}
