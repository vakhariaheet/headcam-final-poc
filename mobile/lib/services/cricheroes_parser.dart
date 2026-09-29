import '../models/match_info.dart';

/// Extracts a CricHeroes match ID from a shared match URL (spec §5.1).
///
/// CricHeroes has no public API, so the app bypasses that by regex-matching
/// the numeric match token out of any standard public match URL the scorer
/// shares, matching spec §5.1's pattern exactly:
/// `(?:cricheroes\.com\/match\/(?:scorecard\/)?)(\d+)`
final RegExp _matchUrlPattern = RegExp(
  r'cricheroes\.com/match/(?:scorecard/)?(\d+)',
  caseSensitive: false,
);

/// Returns the parsed [MatchInfo], or `null` if [input] doesn't contain a
/// recognizable CricHeroes match URL.
MatchInfo? parseCricHeroesUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final match = _matchUrlPattern.firstMatch(trimmed);
  if (match == null) return null;

  final matchId = match.group(1)!;
  final overlayUrl =
      'https://cricheroes.com/overlay/v2/scoreboard?match_id=$matchId&theme=standard';

  return MatchInfo(
    matchId: matchId,
    rawInputUrl: trimmed,
    overlayWebUrl: overlayUrl,
    teamAName: 'Team A',
    teamBName: 'Team B',
  );
}
