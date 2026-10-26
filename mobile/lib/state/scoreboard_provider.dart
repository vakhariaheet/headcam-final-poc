import 'package:flutter_riverpod/flutter_riverpod.dart';

const initialScoreboard = <String, dynamic>{
  'teamA': 'Team A',
  'teamB': 'Team B',
  'runs': 0,
  'wickets': 0,
  'overs': '0.0',
  'caption': '',
};
final scoreboardProvider = StateProvider<Map<String, dynamic>>(
  (ref) => Map.of(initialScoreboard),
);
final broadcastTitleProvider = StateProvider<String>(
  (ref) => 'CreasePoint Live',
);
final broadcastPrivacyProvider = StateProvider<String>((ref) => 'private');
final broadcastTargetProvider = StateProvider<String>((ref) => 'youtube');
