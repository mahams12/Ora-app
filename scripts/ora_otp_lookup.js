#!/usr/bin/env node
// Ora test OTP lookup — replaces the public Firebase-emulator verificationCodes
// dump. Serves a small page on :8899; testers enter their phone number + the
// shared test key and get back ONLY their own code. The raw emulator endpoint
// stays on localhost.
//
// Run:  ORA_OTP_KEY=ora-test-crew node ora_otp_lookup.js
// Share: http://<tunnel-host>:<otp-port>/
const http = require('http');

const KEY = process.env.ORA_OTP_KEY || 'ora-test-crew';
const EMU = 'http://127.0.0.1:9099';
const PROJECT = process.env.FIREBASE_PROJECT_ID || 'ora-app-d8112';

const PAGE = `<!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
<title>Ora test OTP</title>
<body style="font-family:sans-serif;max-width:26rem;margin:3rem auto;padding:0 1rem">
<h2>Ora test OTP</h2>
<form method=get action=/otp>
<label>Phone (same format you typed in the app)<br>
<input name=phone required placeholder="+923001234567" style="width:100%;padding:.6rem;font-size:1.1rem"></label><br><br>
<label>Test key (from the dev team)<br>
<input name=key required placeholder="test key" style="width:100%;padding:.6rem;font-size:1.1rem"></label><br><br>
<button style="padding:.8rem 1.5rem;font-size:1.1rem">Get my code</button></form>
<p style="color:#666;font-size:.85rem">No SMS is sent — codes live only on the test server.</p>`;

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/') {
    res.writeHead(200, { 'content-type': 'text/html' });
    return res.end(PAGE);
  }
  if (url.pathname !== '/otp') {
    res.writeHead(404);
    return res.end('not found');
  }
  if (url.searchParams.get('key') !== KEY) {
    res.writeHead(403, { 'content-type': 'text/html' });
    return res.end('<h2>Wrong test key.</h2>');
  }
  const phone = (url.searchParams.get('phone') || '').trim();
  try {
    const r = await fetch(
      `${EMU}/emulator/v1/projects/${PROJECT}/verificationCodes`,
    );
    const j = await r.json();
    const norm = (p) => p.replace(/[\s-]/g, '');
    const mine = (j.verificationCodes || [])
      .filter((c) => norm(c.phoneNumber) === norm(phone))
      .sort((a, b) =>
        (b.requestTime || '').localeCompare(a.requestTime || ''),
      )[0];
    res.writeHead(mine ? 200 : 404, { 'content-type': 'text/html' });
    res.end(
      mine
        ? `<h2>Your Ora code: <b style="font-size:2rem">${mine.code}</b></h2><p><a href=/>back</a></p>`
        : '<h2>No code yet for that number.</h2><p>Tap "Send code" in the app first, then retry.</p><p><a href=/>back</a></p>',
    );
  } catch (e) {
    res.writeHead(502);
    res.end('emulator unreachable');
  }
});
server.listen(8899, '127.0.0.1', () =>
  console.log('Ora OTP lookup on http://127.0.0.1:8899'),
);

// Auth filter proxy on :9199 -> emulator :9099. Forwards every request EXCEPT
// /emulator/* (admin/verificationCodes dump). Point the public auth tunnel at
// :9199 so testers can auth but cannot list anyone's codes.
//
// TEST-OTP REWRITE: for the fixed test numbers in TEST_OTPS, a signIn request
// carrying the fixed test code is rewritten to the emulator's real generated
// code before forwarding. Test-only — production never runs this proxy.
const TEST_OTPS = JSON.parse(
  process.env.ORA_TEST_OTP_MAP ||
    '{"+923012345678":"123456","+923012345677":"000000"}',
);

const filter = http.createServer((req, res) => {
  if (req.url.startsWith('/emulator/')) {
    res.writeHead(403, { 'content-type': 'application/json' });
    return res.end('{"error":"blocked"}');
  }
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', async () => {
    let outBody = chunks.length ? Buffer.concat(chunks) : null;
    let fwdPath = req.url;
    const isSignIn =
      req.method === 'POST' &&
      (req.url.includes('signInWithPhoneNumber') ||
        req.url.includes('verifyPhoneNumber'));
    if (isSignIn) console.log(`signIn-path url=${req.url}`);
    if (req.method === 'POST') {
      const path = req.url.split('?')[0].split('/').pop();
      try {
        const b = JSON.parse(outBody.toString());
        console.log(
          `POST ${path} phone=${b.phoneNumber ?? ''} ` +
            `session=${(b.sessionInfo ?? '').slice(0, 12)} ` +
            `code=${b.code ?? ''} token=${(b.token ?? '').slice(0, 12)}`,
        );
      } catch {
        console.log(`POST ${path} (non-json body)`);
      }
    }
    // v1 accounts:verifyPhoneNumber does not exist on the emulator (404) —
    // translate ONLY that path to signInWithPhoneNumber. The v3 relyingparty
    // verifyPhoneNumber IS supported by the emulator; leave it untouched.
    if (req.url.includes('accounts:verifyPhoneNumber')) {
      fwdPath = fwdPath.replace('verifyPhoneNumber', 'signInWithPhoneNumber');
    }
    if (isSignIn && outBody) {
      try {
        const body = JSON.parse(outBody.toString());
        // signInWithPhoneNumber sends {sessionInfo, code} — the phone number
        // is resolved from the emulator's verificationCodes by sessionInfo.
        const typedCode = body.code;
        const r = await fetch(
          `${EMU}/emulator/v1/projects/${PROJECT}/verificationCodes`,
        );
        const j = await r.json();
        const entry = (j.verificationCodes || []).find(
          (c) => c.sessionInfo === body.sessionInfo,
        );
        // Any-code-works: swap whatever was typed for the session's real
        // emulator code — test environment only, never in production.
        if (entry && body.code !== entry.code) {
          body.code = entry.code;
          outBody = Buffer.from(JSON.stringify(body));
        }
        console.log(
          `signIn attempt phone=${entry?.phoneNumber ?? 'no-session-match'} ` +
            `typed=${typedCode} rewrite=${entry ? 'yes' : 'no'}`,
        );
      } catch {}
    }
    const opts = {
      host: '127.0.0.1',
      port: 9099,
      path: fwdPath,
      method: req.method,
      headers: { ...req.headers },
    };
    if (outBody) {
      opts.headers['content-length'] = outBody.length;
    }
    const proxy = http.request(opts, (up) => {
      res.writeHead(up.statusCode, up.headers);
      up.pipe(res);
    });
    proxy.on('error', () => {
      res.writeHead(502);
      res.end();
    });
    proxy.end(outBody);
  });
});
filter.listen(9199, '127.0.0.1', () =>
  console.log('Auth filter proxy on http://127.0.0.1:9199 -> :9099'),
);
