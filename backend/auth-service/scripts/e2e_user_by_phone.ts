import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const phone = process.argv[2];
if (!phone) {
  console.error('usage: e2e_user_by_phone.ts +923012345678');
  process.exit(2);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const saPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ??
  path.join(here, '../secrets/service-account.json');

async function main() {
  if (!getApps().length) {
    initializeApp({ credential: cert(saPath) });
  }
  const auth = getAuth();
  const db = getFirestore();
  let user;
  try {
    user = await auth.getUserByPhoneNumber(phone);
  } catch {
    console.log(JSON.stringify({ phone, registered: false }));
    return;
  }
  const doc = await db.collection('users').doc(user.uid).get();
  console.log(
    JSON.stringify({
      phone,
      uid: user.uid,
      registered: true,
      usersDoc: doc.exists ? doc.data() : null,
    }),
  );
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
