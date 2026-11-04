#!/usr/bin/env node
// Local-only proxy between physical Android devices and the Firebase Auth
// emulator. The Android SDK calls relyingparty/signInWithPhoneNumber, which
// this auth-emulator build does not implement; relyingparty/verifyPhoneNumber
// returns the identical credential payload (idToken, refreshToken, localId),
// so we rewrite the path and let the emulator answer.
//
// Optionally substitutes the emulator's real generated code for whatever the
// tester typed (ORA_PROXY_REWRITE_CODE=1) so device tests are friction-free.
//
// Run:  node scripts/ora_auth_emulator_proxy.js          (listens :9199)
// Then: adb reverse tcp:9099 tcp:9199   (device :9099 → proxy → emulator :9099)
const http = require('http');

const LISTEN = Number(process.env.ORA_PROXY_PORT || 9199);
const LISTEN_HOST = process.env.ORA_PROXY_HOST || '127.0.0.1';
const EMU_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const PROJECT = process.env.FIREBASE_PROJECT_ID || 'ora-app-d8112';
const REWRITE_CODE = process.env.ORA_PROXY_REWRITE_CODE !== '0';

async function realCodeFor(sessionInfo) {
  const r = await fetch(
    `http://${EMU_HOST}/emulator/v1/projects/${PROJECT}/verificationCodes`,
  );
  const j = await r.json();
  const hit = (j.verificationCodes || [])
    .filter((c) => c.sessionInfo === sessionInfo)
    .sort((a, b) => (b.requestTime || '').localeCompare(a.requestTime || ''))[0];
  return hit ? hit.code : null;
}

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', async () => {
    let path = req.url;
    let body = Buffer.concat(chunks);
    console.log(`> ${req.method} ${path.split('?')[0]} (${body.length}b)`);
    if (path.includes('/relyingparty/signInWithPhoneNumber')) {
      path = path.replace(
        '/relyingparty/signInWithPhoneNumber',
        '/relyingparty/verifyPhoneNumber',
      );
      try {
        const parsed = JSON.parse(body.toString('utf8') || '{}');
        if (REWRITE_CODE && parsed.sessionInfo) {
          const real = await realCodeFor(parsed.sessionInfo).catch(() => null);
          if (real && parsed.code !== real) {
            parsed.code = real;
            body = Buffer.from(JSON.stringify(parsed));
          }
        }
      } catch {
        /* forward as-is */
      }
    }
    const upstream = http.request(
      {
        host: EMU_HOST.split(':')[0],
        port: Number(EMU_HOST.split(':')[1]),
        method: req.method,
        path,
        headers: { ...req.headers, 'content-length': body.length },
      },
      (ur) => {
        res.writeHead(ur.statusCode || 502, ur.headers);
        ur.pipe(res);
      },
    );
    upstream.on('error', (e) => {
      res.writeHead(502, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: { message: String(e) } }));
    });
    upstream.write(body);
    upstream.end();
  });
});

server.listen(LISTEN, LISTEN_HOST, () => {
  console.log(
    `auth-emulator proxy ${LISTEN_HOST}:${LISTEN} → ${EMU_HOST} ` +
      `(signInWithPhoneNumber→verifyPhoneNumber, code-rewrite=${REWRITE_CODE})`,
  );
});
