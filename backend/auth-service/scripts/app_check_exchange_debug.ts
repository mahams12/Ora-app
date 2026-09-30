/**
 * Exchange a Firebase App Check debug secret (UUID) for a short-lived App Check JWT.
 * Never log the secret or JWT. Uses Android app API key from google-services.json only.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');

const ANDROID_APP_ID = '1:498169438285:android:3b100b1c7a7248f1ddbc04';
const PROJECT_NUMBER = '498169438285';

export function readAndroidApiKey(): string {
  const gs = JSON.parse(
    readFileSync(
      path.join(repoRoot, 'mobile/android/app/google-services.json'),
      'utf8',
    ),
  ) as { client: Array<{ api_key: Array<{ current_key: string }> }> };
  return gs.client[0]!.api_key[0]!.current_key;
}

/** Returns App Check token JWT (do not log). */
export async function exchangeAppCheckDebugSecret(
  debugSecret: string,
): Promise<string> {
  const apiKey = readAndroidApiKey();
  const url =
    `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/apps/${ANDROID_APP_ID}:exchangeDebugToken?key=${encodeURIComponent(apiKey)}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ debugToken: debugSecret.trim(), limitedUse: false }),
  });
  const body = (await res.json()) as { token?: string; error?: { message?: string } };
  if (!res.ok || !body.token) {
    throw new Error(
      `App Check debug exchange failed: ${body.error?.message ?? res.status}`,
    );
  }
  return body.token;
}
