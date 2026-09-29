/**
 * D1 — FCM send boundary (injectable for tests).
 * Exactly-once delivery is NOT claimed; at-least-once wake-up only.
 */

export type FcmSendResult = 'ok' | 'invalid_token' | 'transient_error';

export interface FcmSender {
  sendDataOnly(input: {
    token: string;
    data: Record<string, string>;
  }): Promise<FcmSendResult>;
}

/**
 * Classify Firebase Admin Messaging error codes.
 *
 * Only explicit registration-token failures → invalid_token (token may be deleted).
 * `messaging/invalid-argument` is NOT an invalid-token signal (H4) — treat as transient.
 */
export function classifyFcmAdminError(code: string): FcmSendResult {
  const c = code.toLowerCase();
  if (
    c.includes('registration-token-not-registered') ||
    c.includes('invalid-registration-token')
  ) {
    return 'invalid_token';
  }
  return 'transient_error';
}

/** No-op sender used when Firebase Messaging is unavailable. */
export function createNullFcmSender(): FcmSender {
  return {
    async sendDataOnly() {
      return 'transient_error';
    },
  };
}

/**
 * Real Firebase Admin Messaging sender.
 * Data-only messages (no `notification` key).
 */
export function createFirebaseFcmSender(): FcmSender {
  return {
    async sendDataOnly(input) {
      try {
        const { getMessaging } = await import('firebase-admin/messaging');
        await getMessaging().send({
          token: input.token,
          data: input.data,
        });
        return 'ok';
      } catch (err: unknown) {
        const code =
          err && typeof err === 'object' && 'code' in err
            ? String((err as { code: unknown }).code)
            : '';
        return classifyFcmAdminError(code);
      }
    },
  };
}
