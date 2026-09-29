import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/cricheroes_parser.dart';

void main() {
  group('parseCricHeroesUrl', () {
    test('extracts the match ID from the spec\'s example URL (§5.1)', () {
      final result = parseCricHeroesUrl(
        'https://cricheroes.com/match/scorecard/9482014/final-super-strikers-vs-royal-lions',
      );

      expect(result, isNotNull);
      expect(result!.matchId, '9482014');
      expect(
        result.overlayWebUrl,
        'https://cricheroes.com/overlay/v2/scoreboard?match_id=9482014&theme=standard',
      );
    });

    test('extracts the match ID without the /scorecard/ segment', () {
      final result = parseCricHeroesUrl('https://cricheroes.com/match/9482014');
      expect(result?.matchId, '9482014');
    });

    test('is case-insensitive on the domain', () {
      final result = parseCricHeroesUrl(
        'https://CricHeroes.com/match/scorecard/123',
      );
      expect(result?.matchId, '123');
    });

    test('returns null for an unrelated URL', () {
      expect(parseCricHeroesUrl('https://example.com/match/123'), isNull);
    });

    test('returns null for empty or whitespace input', () {
      expect(parseCricHeroesUrl(''), isNull);
      expect(parseCricHeroesUrl('   '), isNull);
    });

    test('returns null when the URL has no numeric match ID', () {
      expect(
        parseCricHeroesUrl('https://cricheroes.com/match/scorecard/'),
        isNull,
      );
    });
  });
}
