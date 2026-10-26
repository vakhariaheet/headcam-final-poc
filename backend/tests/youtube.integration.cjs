// Run against the disposable database documented in cloud/YOUTUBE.md.
const assert = require('node:assert/strict');
const { randomBytes, randomUUID } = require('node:crypto');
const { test } = require('node:test');

assert.match(process.env.DATABASE_URL || '', /127\.0\.0\.1:25432\/hat_test$/);
process.env.GOOGLE_CLIENT_ID = 'test-client';
process.env.GOOGLE_CLIENT_SECRET = 'test-client-secret';
process.env.GOOGLE_REDIRECT_URI = 'https://api.example.com/api/v1/youtube/oauth/callback';
process.env.YOUTUBE_TOKEN_KEY = randomBytes(32).toString('hex');
process.env.WORKER_API_SECRET = randomBytes(32).toString('hex');
const { createApp } = require('../dist/app');
const { signSessionToken } = require('../dist/auth/tokens');
const { pool } = require('../dist/db');
const { decryptSecret, encryptSecret } = require('../dist/youtube/crypto');

test('OAuth state, encryption, ownership, YouTube setup/stop and disconnect', async () => {
  const app = createApp();
  const userId = randomUUID();
  const sessionId = randomUUID();
  const token = signSessionToken({ sub: userId, email: 'test@example.com', role: 'UMPIRE' });
  const auth = {
    authorization: `Bearer ${token}`,
  };
  const internal = { 'x-worker-secret': process.env.WORKER_API_SECRET };
  const realFetch = global.fetch;
  const calls = [];
  let failBind = false;
  global.fetch = async (url, options = {}) => {
    calls.push(String(url));
    if (String(url).includes('/token')) {
      return Response.json({
        access_token: 'access-test',
        refresh_token: 'refresh-test',
      });
    }
    if (String(url).includes('/revoke')) return new Response('', { status: 200 });
    const uri = new URL(url);
    if (uri.pathname.endsWith('/channels')) {
      return Response.json({
        items: [{ id: 'channel-test', snippet: { title: 'Test Channel' } }],
      });
    }
    if (uri.pathname.endsWith('/liveBroadcasts/bind')) {
      return failBind
        ? new Response('{}', { status: 403 })
        : Response.json({ id: 'broadcast-test' });
    }
    if (uri.pathname.endsWith('/liveBroadcasts/transition')) {
      return Response.json({ id: 'broadcast-test' });
    }
    if (options.method === 'DELETE') return new Response(null, { status: 204 });
    if (uri.pathname.endsWith('/liveBroadcasts') && options.method === 'POST') {
      assert.equal(JSON.parse(options.body).status.privacyStatus, 'private');
      return Response.json({ id: 'broadcast-test' });
    }
    if (uri.pathname.endsWith('/liveStreams')) {
      return Response.json({
        id: 'stream-test',
        cdn: {
          ingestionInfo: {
            rtmpsIngestionAddress: 'rtmps://a.rtmps.youtube.com/live2',
            streamName: 'secret-stream-test',
          },
        },
      });
    }
    if (uri.pathname.endsWith('/liveBroadcasts')) {
      return Response.json({
        items: [{ status: { lifeCycleStatus: 'live' } }],
      });
    }
    throw new Error('Unexpected Google request');
  };
  try {
    await pool.query(
      "INSERT INTO users (id,email,first_name,password_hash) VALUES ($1,$2,$3,'test-only-hash')",
      [userId, `${userId}@example.com`, 'Test'],
    );
    assert.equal(
      (await app.inject({ method: 'POST', url: '/api/v1/youtube/connect' }))
        .statusCode,
      401,
    );
    const connect = await app.inject({
      method: 'POST',
      url: '/api/v1/youtube/connect',
      headers: auth,
    });
    assert.equal(connect.statusCode, 200);
    const state = new URL(connect.json().authorizationUrl).searchParams.get(
      'state',
    );
    assert.ok(state);
    const callback = `/api/v1/youtube/oauth/callback?state=${state}&code=test-code`;
    assert.equal((await app.inject(callback)).statusCode, 200);
    assert.equal((await app.inject(callback)).statusCode, 400);
    const connection = (
      await app.inject({ url: '/api/v1/youtube/connection', headers: auth })
    ).json();
    assert.equal(connection.channel.channel_name, 'Test Channel');
    assert.ok(!JSON.stringify(connection).includes('refresh-test'));
    const cipher = (
      await pool.query(
        'SELECT refresh_token_cipher FROM youtube_connections WHERE user_id=$1',
        [userId],
      )
    ).rows[0].refresh_token_cipher;
    assert.notEqual(cipher, 'refresh-test');
    assert.equal(decryptSecret(cipher), 'refresh-test');
    const encrypted = encryptSecret('test');
    const parts = encrypted.split('.');
    parts[1] = randomBytes(16).toString('base64url');
    assert.throws(() => decryptSecret(parts.join('.')));
    await pool.query(
      'INSERT INTO stream_sessions (id,user_id,session_token,status) '
        + "VALUES ($1,$2,$3,'INITIALIZING')",
      [sessionId, userId, randomUUID()],
    );
    const payload = {
      sessionId,
      userId,
      title: 'Test broadcast',
      privacy: 'private',
    };
    assert.equal(
      (
        await app.inject({
          method: 'POST',
          url: '/api/v1/youtube/internal/start',
          payload,
        })
      ).statusCode,
      401,
    );
    failBind = true;
    assert.equal(
      (
        await app.inject({
          method: 'POST',
          url: '/api/v1/youtube/internal/start',
          headers: internal,
          payload,
        })
      ).statusCode,
      503,
    );
    assert.equal(
      (
        await pool.query(
          'SELECT * FROM youtube_broadcasts WHERE session_id=$1',
          [sessionId],
        )
      ).rowCount,
      0,
    );
    failBind = false;
    const started = await app.inject({
      method: 'POST',
      url: '/api/v1/youtube/internal/start',
      headers: internal,
      payload,
    });
    assert.equal(started.statusCode, 200);
    assert.match(started.json().ingestUrl, /^rtmps:/);
    const count = calls.length;
    assert.equal(
      (
        await app.inject({
          method: 'POST',
          url: '/api/v1/youtube/internal/start',
          headers: internal,
          payload,
        })
      ).statusCode,
      200,
    );
    assert.equal(calls.length, count + 1); // Refresh only; no duplicate broadcast.
    assert.equal(
      (
        await app.inject({
          method: 'DELETE',
          url: '/api/v1/youtube/connection',
          headers: auth,
        })
      ).statusCode,
      400,
    );
    assert.equal(
      (
        await app.inject({
          method: 'POST',
          url: '/api/v1/youtube/internal/stop',
          headers: internal,
          payload: { sessionId, userId },
        })
      ).statusCode,
      200,
    );
    assert.equal(
      (
        await app.inject({
          method: 'DELETE',
          url: '/api/v1/youtube/connection',
          headers: auth,
        })
      ).statusCode,
      200,
    );
    const cancelled = await app.inject({
      method: 'POST',
      url: '/api/v1/youtube/connect',
      headers: auth,
    });
    const state2 = new URL(cancelled.json().authorizationUrl).searchParams.get(
      'state',
    );
    await pool.query(
      "UPDATE youtube_oauth_states SET expires_at=now()-interval '1 second' WHERE user_id=$1",
      [userId],
    );
    assert.equal(
      (
        await app.inject(
          `/api/v1/youtube/oauth/callback?state=${state2}&code=expired`,
        )
      ).statusCode,
      400,
    );
  } finally {
    global.fetch = realFetch;
    await pool.query('DELETE FROM youtube_broadcasts WHERE user_id=$1', [
      userId,
    ]);
    await pool.query('DELETE FROM stream_sessions WHERE user_id=$1', [userId]);
    await pool.query('DELETE FROM users WHERE id=$1', [userId]);
    await app.close();
    await pool.end();
  }
});
