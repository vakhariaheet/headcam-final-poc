// Run against a disposable database (see the Tests section of README.md).
const assert = require('node:assert/strict');
const { createHash, randomBytes, randomUUID } = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

assert.match(process.env.DATABASE_URL || '', /127\.0\.0\.1:25432\/hat_test$/);
process.env.FIRMWARE_DIR = path.join(os.tmpdir(), `hat-fw-${randomUUID()}`);
process.env.FIRMWARE_DOWNLOAD_BASE_URL = 'http://192.168.1.20:4000';
const { createApp } = require('../dist/app');
const { signSessionToken } = require('../dist/auth/tokens');
const { pool } = require('../dist/db');
const { downloadBaseUrl, publishRelease } = require('../dist/firmware/firmware.service');

async function createUser() {
  const id = randomUUID();
  await pool.query(
    "INSERT INTO users (id, email, first_name, password_hash) VALUES ($1, $2, 'Test', 'x')",
    [id, `${id}@example.com`],
  );
  const token = signSessionToken({ sub: id, email: `${id}@example.com`, role: 'UMPIRE' });
  return { id, headers: { authorization: `Bearer ${token}` } };
}

const serial = randomBytes(6).toString('hex').toUpperCase();
const report = {
  hardwareModel: 'AMB82_MINI_V1', firmwareVersion: '0.2.0', cameraRestarts: 0, cameraFailed: false,
};

test('linking, relinking, listing, transfer and unlinking a hat', async () => {
  const app = createApp();
  const alice = await createUser();
  const bob = await createUser();
  const listFor = async (user) => app.inject({
    method: 'GET', url: '/api/v1/devices', headers: user.headers,
  });
  try {
    const first = await app.inject({
      method: 'PUT', url: `/api/v1/devices/${serial}`, headers: alice.headers, payload: report,
    });
    assert.equal(first.statusCode, 201);
    const device = first.json();
    assert.equal(device.serialNumber, serial);
    assert.equal(device.firmwareVersion, '0.2.0');
    assert.ok(device.linkedAt && device.lastSeenAt);
    const mac = await pool.query(
      'SELECT mac_address::text AS mac FROM devices WHERE id=$1',
      [device.id],
    );
    assert.equal(mac.rows[0].mac, serial.toLowerCase().match(/../g).join(':'));

    // Reconnecting updates what the hat reported but keeps the link time.
    const again = await app.inject({
      method: 'PUT',
      url: `/api/v1/devices/${serial}`,
      headers: alice.headers,
      payload: { ...report, firmwareVersion: '0.3.0', cameraRestarts: 2 },
    });
    assert.equal(again.statusCode, 200);
    assert.equal(again.json().id, device.id);
    assert.equal(again.json().firmwareVersion, '0.3.0');
    assert.equal(again.json().cameraRestarts, 2);
    assert.equal(again.json().linkedAt, device.linkedAt);

    const list = await listFor(alice);
    assert.equal(list.statusCode, 200);
    assert.deepEqual(list.json().items.map((d) => d.serialNumber), [serial]);

    // A new BLE claim on another phone moves the hat to that account.
    const transfer = await app.inject({
      method: 'PUT', url: `/api/v1/devices/${serial}`, headers: bob.headers, payload: report,
    });
    assert.equal(transfer.statusCode, 200);
    assert.notEqual(transfer.json().linkedAt, device.linkedAt);
    const aliceAfter = await listFor(alice);
    assert.deepEqual(aliceAfter.json().items, []);

    // Only the linked account can unlink; others see 404.
    const denied = await app.inject({
      method: 'DELETE', url: `/api/v1/devices/${serial}`, headers: alice.headers,
    });
    assert.equal(denied.statusCode, 404);
    assert.equal(denied.json().error.code, 'NOT_FOUND');
    const unlinked = await app.inject({
      method: 'DELETE', url: `/api/v1/devices/${serial}`, headers: bob.headers,
    });
    assert.equal(unlinked.statusCode, 204);
    const bobAfter = await listFor(bob);
    assert.deepEqual(bobAfter.json().items, []);

    // Validation and authentication.
    const badSerial = await app.inject({
      method: 'PUT', url: '/api/v1/devices/not-a-serial', headers: alice.headers, payload: report,
    });
    assert.equal(badSerial.statusCode, 400);
    assert.equal(badSerial.json().error.code, 'VALIDATION_ERROR');
    const badVersion = await app.inject({
      method: 'PUT',
      url: `/api/v1/devices/${serial}`,
      headers: alice.headers,
      payload: { ...report, firmwareVersion: '0.2.0"}' },
    });
    assert.equal(badVersion.statusCode, 400);
    const anonymous = await app.inject({ method: 'GET', url: '/api/v1/devices' });
    assert.equal(anonymous.statusCode, 401);
  } finally {
    await pool.query('DELETE FROM devices WHERE serial_number=$1', [serial]);
    await pool.query('DELETE FROM users WHERE id = ANY($1)', [[alice.id, bob.id]]);
    await app.close();
  }
});

test('publishing and downloading firmware releases', async () => {
  const app = createApp();
  const user = await createUser();
  const model = 'AMB82_PRO_V2'; // keeps this test's releases apart from real ones
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'hat-ota-'));
  const older = path.join(dir, 'older.bin');
  const newer = path.join(dir, 'newer.bin');
  await fs.writeFile(older, randomBytes(5000));
  await fs.writeFile(newer, randomBytes(9000));
  const ids = [];
  try {
    ids.push((await publishRelease({
      hardwareModel: model, version: '9.0.0', filePath: older,
    })).id);
    ids.push((await publishRelease({
      hardwareModel: model, version: '9.1.0', filePath: newer, notes: 'Test release',
    })).id);
    await assert.rejects(
      publishRelease({ hardwareModel: model, version: '9.1.0', filePath: newer }),
      /duplicate key/,
    );
    await assert.rejects(
      publishRelease({ hardwareModel: model, version: 'bad version', filePath: newer }),
      /Version may use/,
    );
    const tiny = path.join(dir, 'tiny.bin');
    await fs.writeFile(tiny, randomBytes(10));
    await assert.rejects(
      publishRelease({ hardwareModel: model, version: '9.2.0', filePath: tiny }),
      /Image must be/,
    );

    const list = await app.inject({
      method: 'GET', url: `/api/v1/firmware-releases?hardwareModel=${model}`, headers: user.headers,
    });
    assert.equal(list.statusCode, 200);
    const [latest, previous] = list.json().items;
    assert.equal(latest.version, '9.1.0');
    assert.equal(previous.version, '9.0.0');
    assert.equal(latest.sizeBytes, 9000);
    assert.equal(latest.notes, 'Test release');
    const newerBytes = await fs.readFile(newer);
    assert.equal(latest.sha256, createHash('sha256').update(newerBytes).digest('hex'));
    assert.equal(
      latest.downloadUrl,
      `http://192.168.1.20:4000/api/v1/firmware-releases/${latest.id}/image`,
    );

    // The hat downloads without a token and needs an exact Content-Length.
    const image = await app.inject({
      method: 'GET', url: `/api/v1/firmware-releases/${latest.id}/image`,
    });
    assert.equal(image.statusCode, 200);
    assert.equal(image.headers['content-length'], '9000');
    assert.equal(image.headers['transfer-encoding'], undefined);
    assert.equal(image.headers['content-type'], 'application/octet-stream');
    assert.deepEqual(image.rawPayload, newerBytes);

    const missing = await app.inject({
      method: 'GET', url: `/api/v1/firmware-releases/${randomUUID()}/image`,
    });
    assert.equal(missing.statusCode, 404);
    // A file that no longer matches its record is not served.
    await fs.writeFile(path.join(process.env.FIRMWARE_DIR, `${previous.id}.bin`), 'truncated');
    const corrupt = await app.inject({
      method: 'GET', url: `/api/v1/firmware-releases/${previous.id}/image`,
    });
    assert.equal(corrupt.statusCode, 404);

    const unknownModel = await app.inject({
      method: 'GET', url: '/api/v1/firmware-releases?hardwareModel=NOPE', headers: user.headers,
    });
    assert.equal(unknownModel.statusCode, 400);
    const anonymous = await app.inject({
      method: 'GET', url: `/api/v1/firmware-releases?hardwareModel=${model}`,
    });
    assert.equal(anonymous.statusCode, 401);
  } finally {
    await pool.query('DELETE FROM firmware_releases WHERE id = ANY($1)', [ids]);
    await pool.query('DELETE FROM users WHERE id=$1', [user.id]);
    await fs.rm(dir, { recursive: true, force: true });
    await app.close();
  }
});

test('the hat must be able to reach the download address', () => {
  assert.equal(downloadBaseUrl('https://api.example.com'), 'http://192.168.1.20:4000');
  // Without the setting, the app's own origin only works if it is plain HTTP
  // and not loopback.
  assert.equal(downloadBaseUrl('http://10.0.0.5:4000', null), 'http://10.0.0.5:4000');
  const unreachable = ['https://api.example.com', 'http://localhost:4000', 'http://127.0.0.1:4000'];
  unreachable.forEach((origin) => {
    assert.throws(() => downloadBaseUrl(origin, null), /plain HTTP/);
  });
  assert.throws(() => downloadBaseUrl('http://10.0.0.5', 'not a url'), /not a valid URL/);
});

test.after(async () => {
  await fs.rm(process.env.FIRMWARE_DIR, { recursive: true, force: true });
  await pool.end();
});
