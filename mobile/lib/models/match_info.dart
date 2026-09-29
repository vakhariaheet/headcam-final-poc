/// A parsed CricHeroes match, extracted from a pasted share URL (spec §5.1).
class MatchInfo {
  const MatchInfo({
    required this.matchId,
    required this.rawInputUrl,
    required this.overlayWebUrl,
    required this.teamAName,
    required this.teamBName,
  });

  final String matchId;
  final String rawInputUrl;
  final String overlayWebUrl;

  // CricHeroes has no public API to resolve team names from a match ID
  // (spec §5.1), so these are local placeholders until a real match feed is
  // wired up. The UI clearly labels them as unconfirmed.
  final String teamAName;
  final String teamBName;
}
