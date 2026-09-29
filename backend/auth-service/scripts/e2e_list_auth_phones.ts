import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const saPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ??
  path.join(here, '../secrets/service-account.json');

async function main() {
  if (!getApps().length) {
    initializeApp({ credential: cert(saPath) });
  }
  const auth = getAuth();
  const out: { uid: string; phone?: string }[] = [];
  let pageToken: string | undefined;
  do {
    const res = await auth.listUsers(1000, pageToken);
    for (const u of res.users) {
      if (u.phoneNumber?.startsWith('+923')) {
        out.push({ uid: u.uid, phone: u.phoneNumber });
      }
    }
    pageToken = res.pageToken;
  } while (pageToken);
  console.log(JSON.stringify({ count: out.length, users: out }, null, 2));
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
