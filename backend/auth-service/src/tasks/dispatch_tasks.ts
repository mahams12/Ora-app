/**
 * Cloud Tasks deadline scheduler — event-driven dispatch wake-ups.
 *
 * Why this exists: dispatch waves run on a 5s cadence with a 20s invite TTL,
 * so a once-per-minute sweep cannot drive real-time matching. Cloud Tasks
 * provides durable, retried, second-precision wake-ups against the existing
 * worker-only /v1/internal routes — no always-on infrastructure, and the
 * 1M free operations/month tier covers ORA's scale at $0.
 *
 * Durability model:
 * - Task names embed (rideId, wave, target-second) so duplicate schedulers
 *   dedupe at the queue (ALREADY_EXISTS is success), while ticks remain
 *   idempotent via the create-once wave doc.
 * - A task that fires early lands on tickRide's `not_due` path, which
 *   re-arms a task at the true dispatchNextAt — self-healing under clock
 *   skew or early delivery.
 * - The low-frequency sweep stays armed as the final backstop.
 */

import { GoogleAuth } from 'google-auth-library';
import { logSafe } from '../http/errors';

export interface ScheduledTaskResult {
  created: boolean;
  taskName: string;
}

export interface DispatchTaskScheduler {
  scheduleDispatchTick(input: {
    rideId: string;
    waveNumber: number;
    runAtMs: number;
    correlationId: string;
  }): Promise<ScheduledTaskResult>;
  scheduleRideExpire(input: {
    rideId: string;
    runAtMs: number;
    correlationId: string;
  }): Promise<ScheduledTaskResult>;
}

/** Disabled scheduler — local dev/tests and deployments without the queue. */
export class NoopDispatchTaskScheduler implements DispatchTaskScheduler {
  async scheduleDispatchTick(): Promise<ScheduledTaskResult> {
    return { created: false, taskName: '' };
  }
  async scheduleRideExpire(): Promise<ScheduledTaskResult> {
    return { created: false, taskName: '' };
  }
}

export interface CloudTasksConfig {
  project: string;
  location: string;
  queue: string;
  /** Absolute service base URL tasks POST to, e.g. https://x.run.app */
  targetBaseUrl: string;
  /** Service account that mints the OIDC token on the request. */
  oidcServiceAccount: string;
}

type FetchFn = (
  url: string,
  init: {
    method: string;
    headers: Record<string, string>;
    body: string;
  },
) => Promise<{ status: number; json: () => Promise<unknown> }>;

/** [a-zA-Z0-9_-] only, per Cloud Tasks task-name grammar. */
function safeSegment(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, '-');
}

export class CloudTasksDispatchScheduler implements DispatchTaskScheduler {
  private readonly queuePath: string;

  constructor(
    private readonly config: CloudTasksConfig,
    private readonly auth: { getAccessToken(): Promise<string | null> },
    private readonly fetchFn: FetchFn = fetch as unknown as FetchFn,
  ) {
    this.queuePath =
      `projects/${config.project}/locations/${config.location}` +
      `/queues/${config.queue}`;
  }

  async scheduleDispatchTick(input: {
    rideId: string;
    waveNumber: number;
    runAtMs: number;
    correlationId: string;
  }): Promise<ScheduledTaskResult> {
    const name =
      `tick-${safeSegment(input.rideId)}-w${input.waveNumber}` +
      `-${Math.floor(input.runAtMs / 1000)}`;
    return this.createTask({
      name,
      url:
        `${this.config.targetBaseUrl}` +
        `/v1/internal/rides/${encodeURIComponent(input.rideId)}/dispatch-tick`,
      runAtMs: input.runAtMs,
      correlationId: input.correlationId,
    });
  }

  async scheduleRideExpire(input: {
    rideId: string;
    runAtMs: number;
    correlationId: string;
  }): Promise<ScheduledTaskResult> {
    const name =
      `exp-${safeSegment(input.rideId)}-${Math.floor(input.runAtMs / 1000)}`;
    return this.createTask({
      name,
      url:
        `${this.config.targetBaseUrl}` +
        `/v1/internal/rides/${encodeURIComponent(input.rideId)}/expire`,
      runAtMs: input.runAtMs,
      correlationId: input.correlationId,
    });
  }

  private async createTask(input: {
    name: string;
    url: string;
    runAtMs: number;
    correlationId: string;
  }): Promise<ScheduledTaskResult> {
    const taskName = `${this.queuePath}/tasks/${input.name}`;
    const token = await this.auth.getAccessToken();
    if (!token) {
      throw new Error('Cloud Tasks: no access token available.');
    }
    const res = await this.fetchFn(
      `https://cloudtasks.googleapis.com/v2/${this.queuePath}/tasks`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          task: {
            name: taskName,
            httpRequest: {
              httpMethod: 'POST',
              url: input.url,
              headers: { 'Content-Type': 'application/json' },
              body: Buffer.from('{}', 'utf8').toString('base64'),
              oidcToken: {
                serviceAccountEmail: this.config.oidcServiceAccount,
                audience: this.config.targetBaseUrl,
              },
            },
            scheduleTime: new Date(input.runAtMs).toISOString(),
          },
        }),
      },
    );

    if (res.status === 200 || res.status === 201) {
      return { created: true, taskName };
    }
    // Duplicate task name → another scheduler already armed this wake-up.
    if (res.status === 409) {
      return { created: false, taskName };
    }
    const body = await res.json().catch(() => null);
    const status =
      (body as { error?: { status?: string } } | null)?.error?.status ?? '';
    if (status === 'ALREADY_EXISTS') {
      return { created: false, taskName };
    }
    throw new Error(
      `Cloud Tasks create failed (${res.status}): ${JSON.stringify(body)}`,
    );
  }
}

export interface DispatchTasksEnv {
  enabled: boolean;
  scheduler: DispatchTaskScheduler;
}

/**
 * Builds the scheduler from env. Disabled (noop) unless
 * DISPATCH_TASKS_ENABLED=true and the queue/target wiring is complete —
 * keeps local runs and tests free of Cloud Tasks dependencies.
 */
export function createDispatchTaskSchedulerFromEnv(env: {
  DISPATCH_TASKS_ENABLED?: string;
  TASKS_PROJECT_ID?: string;
  FIREBASE_PROJECT_ID?: string;
  GOOGLE_CLOUD_PROJECT?: string;
  TASKS_LOCATION?: string;
  TASKS_QUEUE?: string;
  TASKS_TARGET_BASE_URL?: string;
  TASKS_OIDC_SERVICE_ACCOUNT?: string;
} = process.env): DispatchTasksEnv {
  if (env.DISPATCH_TASKS_ENABLED !== 'true') {
    return { enabled: false, scheduler: new NoopDispatchTaskScheduler() };
  }
  const project =
    env.TASKS_PROJECT_ID ??
    env.FIREBASE_PROJECT_ID ??
    env.GOOGLE_CLOUD_PROJECT ??
    '';
  const config: CloudTasksConfig = {
    project,
    location: env.TASKS_LOCATION ?? 'us-central1',
    queue: env.TASKS_QUEUE ?? 'ora-dispatch',
    targetBaseUrl: env.TASKS_TARGET_BASE_URL ?? '',
    oidcServiceAccount: env.TASKS_OIDC_SERVICE_ACCOUNT ?? '',
  };
  if (!config.project || !config.targetBaseUrl || !config.oidcServiceAccount) {
    logSafe('DISPATCH_TASKS_DISABLED', {
      operation: 'DISPATCH_TASKS_DISABLED',
      reason:
        'DISPATCH_TASKS_ENABLED=true but TASKS_PROJECT_ID/' +
        'TASKS_TARGET_BASE_URL/TASKS_OIDC_SERVICE_ACCOUNT incomplete',
    });
    return { enabled: false, scheduler: new NoopDispatchTaskScheduler() };
  }
  const auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  return {
    enabled: true,
    scheduler: new CloudTasksDispatchScheduler(config, {
      getAccessToken: async () => {
        const client = await auth.getClient();
        const token = await client.getAccessToken();
        return token.token ?? null;
      },
    }),
  };
}
