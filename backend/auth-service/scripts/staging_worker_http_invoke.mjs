/**
 * Cloud Run Job entry: POST/GET internal worker route on staging API.
 * Secrets via env (ORA_INTERNAL_WORKER_TOKEN from Secret Manager). No tokens logged.
 */
const base = (
  process.env.WORKER_API_BASE_URL ??
  process.env.STAGING_API_BASE_URL ??
  ''
).replace(/\/$/, '');
const path = process.env.WORKER_INVOKER_PATH ?? '';
const method = (process.env.WORKER_INVOKER_METHOD ?? 'POST').toUpperCase();
const token = process.env.ORA_INTERNAL_WORKER_TOKEN ?? '';

if (!base || !path.startsWith('/')) {
  console.log(
    JSON.stringify({
      ok: false,
      error: 'missing WORKER_API_BASE_URL (or STAGING_API_BASE_URL) or WORKER_INVOKER_PATH',
    }),
  );
  process.exit(2);
}
if (token.length < 16) {
  console.log(JSON.stringify({ ok: false, error: 'worker_token_not_configured' }));
  process.exit(2);
}

const url = `${base}${path}`;

const res = await fetch(url, {
  method,
  headers: {
    Accept: 'application/json',
    'X-Ora-Worker-Token': token,
  },
});

let bodySnippet = '';
try {
  const text = await res.text();
  bodySnippet = text.slice(0, 200);
} catch {
  bodySnippet = '';
}

console.log(
  JSON.stringify({
    ok: res.ok,
    httpStatus: res.status,
    path,
    method,
    bodyPreviewLength: bodySnippet.length,
  }),
);

process.exit(res.ok ? 0 : 1);
