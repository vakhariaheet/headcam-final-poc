import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import 'brand_header.dart';

/// Shared, keyboard-safe layout for the light authentication screens.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.showBackButton = true,
  });

  final Widget child;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD8E5F3), width: 1.4),
    );
    return Theme(
      data: base.copyWith(
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: Colors.white,
          border: border,
          enabledBorder: border,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          prefixIconColor: const Color(0xFF475A7B),
          suffixIconColor: const Color(0xFF475A7B),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0085FF),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: base.textTheme.bodyLarge?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: SvgPicture.asset(
                    'lib/assets/creasepoint-auth-arcs.svg',
                    fit: BoxFit.fitWidth,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 430,
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 8, 28, 48),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showBackButton)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: IconButton(
                                  tooltip: 'Back',
                                  icon: const Icon(
                                    Icons.arrow_back_ios_new,
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    if (Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop();
                                    } else {
                                      Navigator.of(context)
                                          .pushReplacementNamed('/welcome');
                                    }
                                  },
                                ),
                              )
                            else
                              const SizedBox(height: 48),
                            const Center(child: BrandHeader(compact: true)),
                            const SizedBox(height: 16),
                            child,
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
}

/// Arrow label used on primary authentication actions.
class AuthButtonLabel extends StatelessWidget {
  const AuthButtonLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Flexible(child: Text(label, textAlign: TextAlign.center)),
      const SizedBox(width: 12),
      const Icon(Icons.arrow_forward, size: 20),
    ],
  );
}

/// Inline heading and supporting text shared by login and signup.
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
          fontSize: 30,
          letterSpacing: -1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: const Color(0xFF6B7A9C)),
      ),
      const SizedBox(height: AppSpacing.lg),
    ],
  );
}
