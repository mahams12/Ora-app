
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { readFileSync } from 'node:fs';
const sa = JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS!, 'utf8'));
if (!getApps().length) initializeApp({ credential: cert(sa) });
const db = getFirestore();
const id = "017a7e72-531c-4019-82d0-52a9bf9f3321";
const snap = await db.collection('rides').doc(id).get();
const d = snap.exists ? snap.data() : null;
console.log(JSON.stringify({ exists: snap.exists, state: d?.state, version: d?.version, assignedDriverId: d?.assignedDriverId, closedAt: d?.closedAt ?? null }, null, 2));
