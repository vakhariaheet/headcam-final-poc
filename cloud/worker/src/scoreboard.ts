import fs from 'node:fs';

export interface Scoreboard {
  teamA: string;
  teamB: string;
  runs: number;
  wickets: number;
  overs: string;
  caption: string;
}
export const defaultScoreboard: Scoreboard = {
  teamA: 'Team A',
  teamB: 'Team B',
  runs: 0,
  wickets: 0,
  overs: '0.0',
  caption: '',
};
export const scoreboardSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['teamA', 'teamB', 'runs', 'wickets', 'overs', 'caption'],
  properties: {
    teamA: {
      type: 'string',
      minLength: 1,
      maxLength: 24,
      pattern: '^[^\\x00-\\x1f\\x7f]+$',
    },
    teamB: {
      type: 'string',
      minLength: 1,
      maxLength: 24,
      pattern: '^[^\\x00-\\x1f\\x7f]+$',
    },
    runs: { type: 'integer', minimum: 0, maximum: 9999 },
    wickets: { type: 'integer', minimum: 0, maximum: 10 },
    overs: { type: 'string', pattern: '^\\d{1,3}\\.[0-5]$' },
    caption: {
      type: 'string',
      maxLength: 60,
      pattern: '^[^\\x00-\\x1f\\x7f]*$',
    },
  },
};
export function scoreText(score: Scoreboard): string {
  return `${score.teamA}  ${score.runs}/${score.wickets}  (${score.overs} ov)`
    + `  vs  ${score.teamB}\n${score.caption}`;
}
export function writeScore(file: string, score: Scoreboard): void {
  // Readers never see partial UTF-8 text. The file path comes from mkdtemp.
  fs.writeFileSync(`${file}.next`, scoreText(score), { mode: 0o600 });
  fs.renameSync(`${file}.next`, file);
}
export function videoFilter(scoreFile: string): string {
  const font = process.env.OVERLAY_FONT_FILE
    ?? '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf';
  if (!/^[a-zA-Z0-9_./-]+$/.test(font) || !/^[a-zA-Z0-9_./-]+$/.test(scoreFile)) {
    throw new Error('Unsupported overlay path');
  }
  return [
    'scale=1920:1080:force_original_aspect_ratio=decrease',
    'pad=1920:1080:(ow-iw)/2:(oh-ih)/2', 'setsar=1',
    'drawbox=x=25:y=900:w=1870:h=155:color=black@0.7:t=fill',
    `drawtext=fontfile=${font}:textfile=${scoreFile}:reload=1:expansion=none`
      + ':fontcolor=white:fontsize=34:line_spacing=14:x=45:y=930',
  ].join(',');
}
