import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/match_info.dart';
import '../services/cricheroes_parser.dart';

class MatchSetupState {
  const MatchSetupState({this.rawInput = '', this.matchInfo, this.error});

  final String rawInput;
  final MatchInfo? matchInfo;
  final String? error;

  bool get canContinue => matchInfo != null;
}

/// Screen 4 (spec §6.2): real-time regex parsing of a pasted CricHeroes URL
/// via [parseCricHeroesUrl]. Which channels to broadcast to is no longer
/// chosen here — see broadcast_channels_provider.dart's doc comment —
/// match_setup_screen.dart reads that provider directly instead.
class MatchSetupNotifier extends Notifier<MatchSetupState> {
  @override
  MatchSetupState build() => const MatchSetupState();

  void updateInput(String value) {
    if (value.trim().isEmpty) {
      state = const MatchSetupState();
      return;
    }
    final parsed = parseCricHeroesUrl(value);
    state = MatchSetupState(
      rawInput: value,
      matchInfo: parsed,
      error: parsed == null
          ? "That doesn't look like a CricHeroes match URL."
          : null,
    );
  }
}

final matchSetupProvider =
    NotifierProvider<MatchSetupNotifier, MatchSetupState>(
      MatchSetupNotifier.new,
    );
