const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

const jwt = require('jsonwebtoken');

const { pool } = require('../dist/db');
const {
  defaultScoreboard,
  videoFilter,
  writeScore,
} = require('../dist/scoreboard');
const { buildApp } = require('../dist/server');

test('scoreboard text is data, and unsafe fields/unauthorized edits fail', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hat-score-test-'));
  const file = path.join(dir, 'score.txt');
  const app = buildApp();
  try {
    writeScore(file, {
      ...defaultScoreboard,
      caption: '%{metadata:secret}:[]',
    });
    assert.ok(fs.readFileSync(file, 'utf8').includes('%{metadata:secret}:[]'));
    assert.ok(videoFilter(file).includes('expansion=none'));
    assert.ok(!videoFilter(file).includes('metadata:secret'));
    const token = jwt.sign(
      { sub: randomUUID() },
      process.env.JWT_SECRET || 'umpirehat-dev-secret-change-me',
    );
    const headers = {
      authorization: `Bearer ${token}`,
    };
    assert.equal(
      (
        await app.inject({
          method: 'PATCH',
          url: `/sessions/${randomUUID()}/scoreboard`,
          payload: defaultScoreboard,
        })
      ).statusCode,
      401,
    );
    await Promise.all([
      { overs: '3.6' },
      { wickets: 11 },
      { teamA: 'bad\nline' },
      { caption: 'x'.repeat(61) },
      { extra: 'field' },
    ].map(async (bad) => {
      assert.equal(
        (
          await app.inject({
            method: 'PATCH',
            url: `/sessions/${randomUUID()}/scoreboard`,
            headers,
            payload: { ...defaultScoreboard, ...bad },
          })
        ).statusCode,
        400,
      );
    }));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
    await app.close();
    await pool.end();
  }
});
