// Starts a local Cloud Firestore emulator for the Feedback UI tests (FeedbackBatchFBAUITests).
//
// The emulator listens only on 127.0.0.1, on a free port that is never 8080, and enforces the real
// firebase/firestore.rules. It uses the app's own project id because the app's Firebase SDK names it in
// every request; nothing here or in the app's UI-test mode ever leaves this Mac.
//
// It prints one line, "MATHSQUEST_FEEDBACK_EMULATOR_PORT=<port>", then keeps running until it is
// stopped (Ctrl-C or SIGTERM). Pass that port to the UI tests:
//
//   node firebase/tests/feedback-emulator.mjs
//   TEST_RUNNER_MATHSQUEST_FEEDBACK_EMULATOR_PORT=<port> xcodebuild test ... \
//     -only-testing:"Maths QuestUITests/FeedbackBatchFBAUITests"
//
// Needs Node 18+, Java 11+ and the Firestore emulator JAR that firebase-tools downloads to
// ~/.cache/firebase/emulators/ (or set FIRESTORE_EMULATOR_JAR).

import { spawn } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const RULES_FILE = join(HERE, '..', 'firestore.rules');
const PLIST = join(HERE, '..', '..', 'Maths Quest', 'GoogleService-Info.plist');

function appProjectId() {
  const match = readFileSync(PLIST, 'utf8').match(/<key>PROJECT_ID<\/key>\s*<string>([^<]+)<\/string>/);
  if (!match) throw new Error(`No PROJECT_ID in ${PLIST}`);
  return match[1];
}

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

async function freePortOtherThan8080() {
  for (;;) {
    const port = await freePort();
    if (port !== 8080) return port;
  }
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

const project = appProjectId();
const port = await freePortOtherThan8080();
const websocketPort = await freePortOtherThan8080();
const emulator = spawn(process.env.JAVA ?? 'java', [
  '-jar', findJar(),
  '--host', '127.0.0.1', '--port', String(port), '--websocket_port', String(websocketPort),
  '--project_id', project, '--single_project_mode', 'true',
], { stdio: ['ignore', 'pipe', 'pipe'] });

let log = '';
emulator.stdout.on('data', (d) => { log += d; });
emulator.stderr.on('data', (d) => { log += d; });
const stop = () => { emulator.kill(); };
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
emulator.on('exit', (code) => process.exit(code ?? 0));

const base = `http://127.0.0.1:${port}`;
let ready = false;
for (let i = 0; i < 240 && emulator.exitCode === null; i++) {
  try { await fetch(base); ready = true; break; } catch { await new Promise((r) => setTimeout(r, 250)); }
}
if (!ready) {
  stop();
  console.error(`Firestore emulator did not start:\n${log}`);
  process.exit(1);
}

const res = await fetch(`${base}/emulator/v1/projects/${project}:securityRules`, {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ rules: { files: [{ name: 'firestore.rules', content: readFileSync(RULES_FILE, 'utf8') }] } }),
});
if (res.status !== 200) {
  stop();
  console.error(`Emulator rejected the rules: ${await res.text()}`);
  process.exit(1);
}

console.log(`MATHSQUEST_FEEDBACK_EMULATOR_PORT=${port}`);
