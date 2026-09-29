import 'package:flutter/material.dart';

/// The app's logo lockup, reused on the splash screen, Login, and Signup
/// for a consistent identity instead of a plain text title on every
/// screen.
///
/// The two source images ([lib/assets/creasepoint-dark.png] and
/// [lib/assets/creasepoint-white.png]) are each a complete mark+wordmark
/// square on their own solid background — not a transparent icon to pair
/// with separately-rendered text. `creasepoint-dark.png`'s navy background
/// is the same [AppColors.navy900] the Live console uses, so it's the
/// right choice there; `creasepoint-white.png`'s white background reads
/// correctly against the app's light screens. See [onDark].
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.compact = false, this.onDark = false});

  final bool compact;

  /// True when rendered against the dark/navy Live console background —
  /// picks the navy-background lockup instead of the white-background one.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final asset = onDark
        ? 'lib/assets/creasepoint-dark.png'
        : 'lib/assets/creasepoint-white.png';

    // The source lockups are square images with substantial whitespace above
    // and below the artwork. Crop that whitespace in compact auth headers so
    // the logo does not push the form's final action below the fold.
    if (compact) {
      return ClipRect(
        child: SizedBox(
          width: 160,
          height: 88,
          child: OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxWidth: 160,
            maxHeight: 160,
            child: Image.asset(
              asset,
              width: 160,
              height: 160,
              semanticLabel: 'CreasePoint',
            ),
          ),
        ),
      );
    }

    return Image.asset(
      asset,
      width: 220,
      height: 220,
      semanticLabel: 'CreasePoint',
    );
  }
}
