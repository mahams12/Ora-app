import type { Request, Response, NextFunction } from 'express';
import { OAuth2Client } from 'google-auth-library';
import { sendApiError } from '../http/errors';

export interface InternalOidcConfig {
  /** Expected token audience — the service base URL tasks POST to. */
  audience: string;
  /** Allowed invoker service-account emails (e.g. the tasks invoker SA). */
  allowedEmails: ReadonlySet<string>;
  /**
   * Injectable for tests — defaults to Google OIDC verification via
   * google-auth-library's OAuth2Client.
   */
  verifyIdToken?: (
    token: string,
    audience: string,
  ) => Promise<{ email?: string; email_verified?: boolean }>;
}

const defaultVerifier = (() => {
  let client: OAuth2Client | null = null;
  return async (
    token: string,
    audience: string,
  ): Promise<{ email?: string; email_verified?: boolean }> => {
    client ??= new OAuth2Client();
    const ticket = await client.verifyIdToken({
      idToken: token,
      audience,
    });
    const payload = ticket.getPayload();
    return {
      email: payload?.email,
      email_verified: payload?.email_verified === true,
    };
  };
})();

/**
 * Service-authenticated internal worker boundary (Phase 2J).
 * Not a passenger/driver Firebase JWT path.
 *
 * Two accepted credentials:
 * 1. X-Ora-Worker-Token shared secret (Cloud Scheduler → job → HTTP invoke).
 * 2. Authorization: Bearer <Google OIDC id_token> from an allowlisted service
 *    account (Cloud Tasks push). Verified signature + audience + email —
 *    unauthorized callers cannot tick dispatch or expire rides.
 */
export function createInternalWorkerMiddleware(
  expectedToken: string | undefined,
  oidc?: InternalOidcConfig,
) {
  const tokenConfigured = !!expectedToken && expectedToken.length >= 16;
  const oidcConfigured =
    !!oidc && oidc.allowedEmails.size > 0 && !!oidc.audience;
  const verify = oidc?.verifyIdToken ?? defaultVerifier;

  return async (
    req: Request,
    res: Response,
    next: NextFunction,
  ): Promise<void> => {
    if (!tokenConfigured && !oidcConfigured) {
      sendApiError(
        req,
        res,
        503,
        'INTERNAL',
        'Internal worker authentication is not configured.',
      );
      return;
    }

    const provided = req.header('X-Ora-Worker-Token') ?? '';
    if (tokenConfigured && provided === expectedToken) {
      next();
      return;
    }

    const authz = req.header('Authorization') ?? '';
    if (oidcConfigured && authz.startsWith('Bearer ')) {
      try {
        const payload = await verify(authz.slice(7), oidc!.audience);
        if (
          payload.email_verified === true &&
          payload.email != null &&
          oidc!.allowedEmails.has(payload.email)
        ) {
          next();
          return;
        }
      } catch {
        // fall through to 403
      }
    }

    sendApiError(req, res, 403, 'FORBIDDEN', 'Invalid worker credentials.');
  };
}
