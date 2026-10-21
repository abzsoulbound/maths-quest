// Security tests for firebase/firestore.rules and the app's Firestore usage.
//
// Runs only against a local Cloud Firestore emulator on 127.0.0.1 with the project id
// "demo-maths-quest". "demo-" ids can never resolve to a real Firebase project, and the
// script refuses any non-local emulator address, so production is never contacted.
//
// Needs Node 18+, Java 11+ and the Firestore emulator JAR, which firebase-tools
// downloads to ~/.cache/firebase/emulators/ (`npx firebase-tools setup:emulators:firestore`).
// Set FIRESTORE_EMULATOR_JAR to use another JAR, or FIRESTORE_EMULATOR_HOST to use an
// emulator that is already running.
//
// From the repository root:
//   node firebase/tests/firestore-rules.test.mjs

import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';

const HERE = dirname(fileURLToPath(import.meta.url));
const RULES_FILE = join(HERE, '..', 'firestore.rules');
const SWIFT_FILE = join(HERE, '..', '..', 'Maths Quest', 'ContentView.swift');
const PROJECT = 'demo-maths-quest';

const OPEN_RULES = `rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} { allow read, write: if true; }
  }
}`;

// ---------------------------------------------------------------------------
// Emulator

let base;
let emulator;

function freePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

function findJar() {
  if (process.env.FIRESTORE_EMULATOR_JAR) return process.env.FIRESTORE_EMULATOR_JAR;
  const dir = join(homedir(), '.cache', 'firebase', 'emulators');
  const jars = existsSync(dir)
    ? readdirSync(dir).filter((f) => /^cloud-firestore-emulator-v[\d.]+\.jar$/.test(f))
    : [];
  if (jars.length === 0) {
    throw new Error('Firestore emulator JAR not found. Run `npx firebase-tools setup:emulators:firestore` or set FIRESTORE_EMULATOR_JAR.');
  }
  jars.sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  return join(dir, jars.at(-1));
}

async function startEmulator() {
  const existing = process.env.FIRESTORE_EMULATOR_HOST;
  if (existing) {
    assert.match(existing, /^(127\.0\.0\.1|localhost|\[::1\]):\d+$/, `Refusing non-local FIRESTORE_EMULATOR_HOST=${existing}`);
    base = `http://${existing}`;
    return;
  }
  const port = await freePort();
  const websocketPort = await freePort();
  emulator = spawn(process.env.JAVA ?? 'java', [
    '-jar', findJar(),
    '--host', '127.0.0.1', '--port', String(port), '--websocket_port', String(websocketPort),
    '--project_id', PROJECT, '--single_project_mode', 'true',
  ], { stdio: ['ignore', 'pipe', 'pipe'] });
  let log = '';
  emulator.stdout.on('data', (d) => { log += d; });
  emulator.stderr.on('data', (d) => { log += d; });
  base = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 240 && emulator.exitCode === null; i++) {
    try { await fetch(base); return; } catch { await new Promise((r) => setTimeout(r, 250)); }
  }
  emulator.kill();
  throw new Error(`Firestore emulator did not start:\n${log}`);
}

async function loadRules(content) {
  const res = await fetch(`${base}/emulator/v1/projects/${PROJECT}:securityRules`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ rules: { files: [{ name: 'firestore.rules', content }] } }),
  });
  assert.equal(res.status, 200, `Emulator rejected the rules: ${await res.text()}`);
}

async function resetData() {
  const res = await fetch(`${base}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(res.status, 200);
  // Seed one existing feedback document as the emulator owner, which bypasses rules.
  const seeded = await request('POST', '/feedbacks?documentId=existing', 'owner', { fields: feedback('seeded feedback') });
  assert.equal(seeded.status, 200, seeded.body);
}

// ---------------------------------------------------------------------------
// Requests

const b64url = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');

// Unsigned ID token for a signed-in, non-admin user; the emulator accepts these.
function mockIdToken(uid) {
  const now = Math.floor(Date.now() / 1000);
  return `${b64url({ alg: 'none', typ: 'JWT' })}.${b64url({
    iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, sub: uid, user_id: uid,
    iat: now, exp: now + 3600, auth_time: now, firebase: { sign_in_provider: 'anonymous', identities: {} },
  })}.`;
}

const HEADERS = {
  anonymous: {}, // what the app sends: it has no Firebase Auth
  signedIn: { Authorization: `Bearer ${mockIdToken('some-user')}` },
  owner: { Authorization: 'Bearer owner' },
};

async function request(method, path, as, body) {
  const res = await fetch(`${base}/v1/projects/${PROJECT}/databases/(default)/documents${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...HEADERS[as] },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.text() };
}

// 200 = allowed. 404 NOT_FOUND = allowed: rules run before the existence check, so a get
// the rules permit on a missing document reports 404. 403 PERMISSION_DENIED = denied.
function outcome({ status, body }) {
  if (status === 200 || status === 404) return 'allowed';
  if (status === 403 && body.includes('PERMISSION_DENIED')) return 'denied';
  throw new Error(`Unexpected emulator response ${status}: ${body}`);
}

const autoId = () => randomBytes(10).toString('hex');
const docName = (path) => `projects/${PROJECT}/databases/(default)/documents/${path}`;

// The document FeedbackView.submitFeedback() writes: ["text": feedbackText, "timestamp": Timestamp()]
function feedback(text = 'I love the Year 3 times tables!', extra = {}) {
  return { text: { stringValue: text }, timestamp: { timestampValue: new Date().toISOString() }, ...extra };
}

// addDocument in the iOS SDK is a commit with a "must not already exist" precondition.
function addDocument(fields, as = 'anonymous') {
  return request('POST', ':commit', as, {
    writes: [{ update: { name: docName(`feedbacks/${autoId()}`), fields }, currentDocument: { exists: false } }],
  });
}

function query(structuredQuery, as = 'anonymous') {
  return request('POST', ':runQuery', as, { structuredQuery });
}

// What the removed in-app admin screen ran: every feedback, newest first.
const ALL_FEEDBACK = {
  from: [{ collectionId: 'feedbacks' }],
  orderBy: [{ field: { fieldPath: 'timestamp' }, direction: 'DESCENDING' }],
};

const allowed = async (call) => assert.equal(outcome(await call), 'allowed');
const denied = async (call) => assert.equal(outcome(await call), 'denied');

// ---------------------------------------------------------------------------

before(startEmulator);
after(() => emulator?.kill());

describe('proposed rules: firebase/firestore.rules', () => {
  before(async () => {
    await loadRules(readFileSync(RULES_FILE, 'utf8'));
    await resetData();
  });

  describe('feedback submission keeps working', () => {
    test('the app document, sent the way the iOS SDK sends addDocument', () => allowed(addDocument(feedback())));
    test('the app document, sent with REST createDocument', () => allowed(request('POST', '/feedbacks', 'anonymous', { fields: feedback() })));
    test('a signed-in user, in case sign-in is added later', () => allowed(addDocument(feedback(), 'signedIn')));
    test('long feedback (100,000 characters): no length limit is imposed', () => allowed(addDocument(feedback('x'.repeat(100_000)))));
    test('whitespace-only, emoji and multi-line text, which the app accepts', async () => {
      await allowed(addDocument(feedback('   \n ')));
      await allowed(addDocument(feedback('👍 Great app!\n\nMore fractions please 🙏')));
    });
  });

  describe('malformed feedback is rejected', () => {
    test('an extra field', () => denied(addDocument(feedback(undefined, { isAdmin: { booleanValue: true } }))));
    test('a missing timestamp', () => denied(addDocument({ text: { stringValue: 'hi' } })));
    test('missing text', () => denied(addDocument({ timestamp: { timestampValue: new Date().toISOString() } })));
    test('empty text', () => denied(addDocument(feedback(''))));
    test('text that is not a string', () => denied(addDocument({ ...feedback(), text: { integerValue: '42' } })));
    test('a timestamp sent as a string', () => denied(addDocument({ ...feedback(), timestamp: { stringValue: new Date().toISOString() } })));
    test('a timestamp sent as a number', () => denied(addDocument({ ...feedback(), timestamp: { integerValue: String(Date.now()) } })));
  });

  describe('no client can read feedback', () => {
    test('get an existing document', () => denied(request('GET', '/feedbacks/existing', 'anonymous')));
    test('get an existing document while signed in', () => denied(request('GET', '/feedbacks/existing', 'signedIn')));
    test('get a missing document (the production probe; must be 403, not 404)', () => denied(request('GET', `/feedbacks/${autoId()}`, 'anonymous')));
    test('list all feedback, as the removed admin screen did', () => denied(query(ALL_FEEDBACK)));
    test('list all feedback while signed in', () => denied(query(ALL_FEEDBACK, 'signedIn')));
    test('a query that matches nothing', () => denied(query({
      from: [{ collectionId: 'feedbacks' }],
      where: { fieldFilter: { field: { fieldPath: 'text' }, op: 'EQUAL', value: { stringValue: autoId() } } },
    })));
    test('a collection-group query', () => denied(query({ from: [{ collectionId: 'feedbacks', allDescendants: true }] })));
  });

  describe('no client can change or delete feedback', () => {
    test('overwrite an existing document', () => denied(request('PATCH', '/feedbacks/existing', 'anonymous', { fields: feedback('tampered') })));
    test('overwrite an existing document while signed in', () => denied(request('PATCH', '/feedbacks/existing', 'signedIn', { fields: feedback('tampered') })));
    test('delete an existing document, as the removed admin screen did', () => denied(request('DELETE', '/feedbacks/existing', 'anonymous')));
    test('delete an existing document while signed in', () => denied(request('DELETE', '/feedbacks/existing', 'signedIn')));
    test('the existing document is unchanged afterwards', async () => {
      const res = await request('GET', '/feedbacks/existing', 'owner');
      assert.equal(res.status, 200, res.body);
      assert.equal(JSON.parse(res.body).fields.text.stringValue, 'seeded feedback');
    });
  });

  describe('everything else is closed', () => {
    test('write to another collection', () => denied(request('POST', '/users', 'anonymous', { fields: feedback() })));
    test('read another collection', () => denied(request('GET', '/users/someone', 'anonymous')));
    test('write to a subcollection of a feedback document', () => denied(request('POST', '/feedbacks/existing/replies', 'anonymous', { fields: feedback() })));
  });
});

// Proves the checks above can fail: with fully open rules the same requests must succeed.
describe('harness self-check: fully open rules are detected', () => {
  before(async () => {
    await loadRules(OPEN_RULES);
    await resetData();
  });

  test('malformed feedback is accepted', () => allowed(addDocument(feedback(undefined, { isAdmin: { booleanValue: true } }))));
  test('feedback can be read and listed', async () => {
    await allowed(request('GET', '/feedbacks/existing', 'anonymous'));
    await allowed(query(ALL_FEEDBACK));
  });
  test('a missing document returns 404 when reads are allowed (the production result on 2026-10-12)', async () => {
    const res = await request('GET', `/feedbacks/${autoId()}`, 'anonymous');
    assert.equal(res.status, 404, res.body);
  });
  test('feedback can be overwritten and deleted', async () => {
    await allowed(request('PATCH', '/feedbacks/existing', 'anonymous', { fields: feedback('tampered') }));
    await allowed(request('DELETE', '/feedbacks/existing', 'anonymous'));
  });
});

// Keeps the rules and the app in step: if the app's Firestore usage changes, update the rules.
describe('client contract: Maths Quest/ContentView.swift', () => {
  const source = readFileSync(SWIFT_FILE, 'utf8');

  test('the only Firestore call is addDocument on "feedbacks"', () => {
    assert.deepEqual(source.match(/\.collection\("[^"]*"\)\.\w+/g), ['.collection("feedbacks").addDocument']);
    for (const api of ['getDocument', 'addSnapshotListener', '.delete(', 'updateData', 'setData', 'collectionGroup', 'runTransaction']) {
      assert.ok(!source.includes(api), `unexpected Firestore API in app: ${api}`);
    }
  });

  test('the feedback document has exactly the fields the rules allow', () => {
    assert.match(source, /"text":\s*feedbackText,\s*"timestamp":\s*Timestamp\(\)\s*\]/);
  });

  test('no hidden admin screen or cheat codes (MQ-04)', () => {
    for (const marker of ['1937', 'UserFeedbackView', 'Admin Only', 'navigateToFeedbacks']) {
      assert.ok(!source.includes(marker), `found "${marker}"`);
    }
  });
});
