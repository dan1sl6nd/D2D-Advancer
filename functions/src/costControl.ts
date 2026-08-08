export interface FixedWindowRateLimitPolicy {
  maxRequests: number;
  windowMs: number;
}

export interface FixedWindowRateLimitState {
  count: number;
  windowStartedAtMillis: number;
}

export interface FixedWindowRateLimitDecision extends FixedWindowRateLimitState {
  allowed: boolean;
  retryAfterSeconds: number;
}

export interface TeamBudgetDecision {
  alertThreshold: number | null;
  budgetAmount: number | null;
  costAmount: number | null;
  costRatio: number | null;
  currencyCode: string | null;
  shouldPauseTeamWrites: boolean;
}

export type TeamUsageLevel = "normal" | "warning" | "limited";

export interface TeamUsagePolicy {
  dailyWarningWrites: number;
  dailyWriteLimit: number;
  publishIntervalMs: number;
  velocityWarningWrites: number;
  velocityWriteLimit: number;
  velocityWindowMs: number;
  recordLimits: Record<string, number>;
}

export interface TeamUsageCounterState {
  activeRecords: Record<string, number>;
  dailyWrites: number;
  dayKey: string;
  lastPublishedAtMillis: number;
  publishedLevel: TeamUsageLevel;
  velocityWrites: number;
  windowKey: string;
}

export interface TeamUsageMutation {
  collectionId: string;
  recordDelta: number;
}

export interface TeamUsageDecision extends TeamUsageCounterState {
  blockedCollections: string[];
  level: TeamUsageLevel;
  limitedUntilMillis: number | null;
  message: string | null;
  shouldPublish: boolean;
  writesAllowed: boolean;
}

export const CREATE_TEAM_RATE_LIMIT: FixedWindowRateLimitPolicy = {
  maxRequests: 5,
  windowMs: 60 * 60 * 1_000
};

export const INVITE_PREVIEW_RATE_LIMIT: FixedWindowRateLimitPolicy = {
  maxRequests: 60,
  windowMs: 60 * 60 * 1_000
};

export const SYNC_ENTITLEMENT_RATE_LIMIT: FixedWindowRateLimitPolicy = {
  maxRequests: 30,
  windowMs: 60 * 60 * 1_000
};

export const TEAM_BUDGET_LOCK_RATIO = 0.8;
export const TEAM_BUDGET_TOPIC = "d2d-firebase-budget-alerts";
export const TEAM_OPERATIONS_CONTROL_DOCUMENT = "teamOperations";
export const TEAM_OPERATIONS_CONTROL_COLLECTION = "serviceControls";
export const TEAM_OPERATIONS_PAUSED_MESSAGE =
  "Team edits are temporarily paused while usage is checked. Existing team data remains available.";

export const TEAM_USAGE_COUNTER_COLLECTION = "teamUsageCounters";
export const TEAM_USAGE_CONTROL_COLLECTION = "teamUsageControls";
export const TEAM_USAGE_EVENT_COLLECTION = "teamUsageEvents";
export const TEAM_USAGE_EVENT_RETENTION_MS = 2 * 24 * 60 * 60 * 1_000;
export const TEAM_USAGE_POLICY: TeamUsagePolicy = {
  dailyWarningWrites: 3_000,
  dailyWriteLimit: 5_000,
  publishIntervalMs: 5 * 60 * 1_000,
  velocityWarningWrites: 180,
  velocityWriteLimit: 300,
  velocityWindowMs: 15 * 60 * 1_000,
  recordLimits: {
    activityLog: 5_000,
    bookings: 1_500,
    dutyLocationPoints: 100_000,
    leads: 3_000,
    ownerNotifications: 1_000
  }
};

export const METERED_TEAM_COLLECTIONS = new Set([
  "activityLog",
  "bookings",
  "dutyLocationPoints",
  "dutySessions",
  "leads",
  "members",
  "ownerNotifications"
]);

export function evaluateFixedWindowRateLimit(
  previous: FixedWindowRateLimitState | null,
  nowMillis: number,
  policy: FixedWindowRateLimitPolicy
): FixedWindowRateLimitDecision {
  if (policy.maxRequests < 1 || policy.windowMs < 1) {
    throw new Error("Rate-limit policy values must be positive.");
  }

  const startsNewWindow = previous === null
    || previous.count < 0
    || previous.windowStartedAtMillis > nowMillis
    || nowMillis >= previous.windowStartedAtMillis + policy.windowMs;

  if (startsNewWindow) {
    return {
      allowed: true,
      count: 1,
      retryAfterSeconds: 0,
      windowStartedAtMillis: nowMillis
    };
  }

  const windowEndsAt = previous.windowStartedAtMillis + policy.windowMs;
  if (previous.count >= policy.maxRequests) {
    return {
      allowed: false,
      count: previous.count,
      retryAfterSeconds: Math.max(1, Math.ceil((windowEndsAt - nowMillis) / 1_000)),
      windowStartedAtMillis: previous.windowStartedAtMillis
    };
  }

  return {
    allowed: true,
    count: previous.count + 1,
    retryAfterSeconds: 0,
    windowStartedAtMillis: previous.windowStartedAtMillis
  };
}

export function evaluateTeamBudgetAlert(payload: unknown): TeamBudgetDecision {
  const data = isRecord(payload) ? payload : {};
  const costAmount = finiteNumber(data.costAmount);
  const budgetAmount = finiteNumber(data.budgetAmount);
  const alertThreshold = finiteNumber(data.alertThresholdExceeded);
  const costRatio = costAmount !== null && budgetAmount !== null && budgetAmount > 0
    ? costAmount / budgetAmount
    : null;
  const currencyCode = typeof data.currencyCode === "string" && data.currencyCode.trim()
    ? data.currencyCode.trim().slice(0, 12)
    : null;

  return {
    alertThreshold,
    budgetAmount,
    costAmount,
    costRatio,
    currencyCode,
    shouldPauseTeamWrites:
      (costRatio !== null && costRatio >= TEAM_BUDGET_LOCK_RATIO)
      || (alertThreshold !== null && alertThreshold >= TEAM_BUDGET_LOCK_RATIO)
  };
}

export function evaluateTeamUsage(
  previous: TeamUsageCounterState | null,
  mutation: TeamUsageMutation,
  nowMillis: number,
  policy: TeamUsagePolicy = TEAM_USAGE_POLICY
): TeamUsageDecision {
  if (
    policy.dailyWarningWrites < 1
    || policy.dailyWriteLimit < policy.dailyWarningWrites
    || policy.velocityWarningWrites < 1
    || policy.velocityWriteLimit < policy.velocityWarningWrites
    || policy.velocityWindowMs < 1
  ) {
    throw new Error("Team usage policy values are invalid.");
  }

  const dayKey = new Date(nowMillis).toISOString().slice(0, 10);
  const windowNumber = Math.floor(nowMillis / policy.velocityWindowMs);
  const windowKey = String(windowNumber);
  const dailyWrites = previous?.dayKey === dayKey
    ? Math.max(0, previous.dailyWrites) + 1
    : 1;
  const velocityWrites = previous?.windowKey === windowKey
    ? Math.max(0, previous.velocityWrites) + 1
    : 1;
  const activeRecords = { ...(previous?.activeRecords ?? {}) };
  const normalizedDelta = Math.max(-1, Math.min(1, Math.trunc(mutation.recordDelta)));

  if (policy.recordLimits[mutation.collectionId] !== undefined && normalizedDelta !== 0) {
    activeRecords[mutation.collectionId] = Math.max(
      0,
      (activeRecords[mutation.collectionId] ?? 0) + normalizedDelta
    );
  }

  const blockedCollections = Object.entries(policy.recordLimits)
    .filter(([collectionId, limit]) => (activeRecords[collectionId] ?? 0) >= limit)
    .map(([collectionId]) => collectionId)
    .sort();
  const dailyLimitReached = dailyWrites >= policy.dailyWriteLimit;
  const velocityLimitReached = velocityWrites >= policy.velocityWriteLimit;
  const writesAllowed = !dailyLimitReached && !velocityLimitReached;
  const recordWarningReached = Object.entries(policy.recordLimits).some(
    ([collectionId, limit]) => (activeRecords[collectionId] ?? 0) >= Math.ceil(limit * 0.8)
  );
  const warningReached = dailyWrites >= policy.dailyWarningWrites
    || velocityWrites >= policy.velocityWarningWrites
    || recordWarningReached;
  const level: TeamUsageLevel = writesAllowed
    ? warningReached ? "warning" : "normal"
    : "limited";

  let limitedUntilMillis: number | null = null;
  let message: string | null = null;
  if (!writesAllowed) {
    const windowEndsAt = (windowNumber + 1) * policy.velocityWindowMs;
    const nextDay = Date.parse(`${dayKey}T00:00:00.000Z`) + 24 * 60 * 60 * 1_000;
    limitedUntilMillis = dailyLimitReached ? nextDay : windowEndsAt;
    message = dailyLimitReached
      ? "Team edits are paused until tomorrow because today's usage limit was reached. Existing data remains available."
      : "Team edits are paused briefly because activity increased unusually fast. Existing data remains available.";
  } else if (warningReached) {
    message = blockedCollections.length > 0
      ? "Team storage reached an included capacity. Archive old work before adding more records."
      : "Team usage is higher than usual. Live location sharing may update less often to control costs.";
  }

  const previousLevel = previous?.publishedLevel ?? "normal";
  const lastPublishedAtMillis = Math.max(0, previous?.lastPublishedAtMillis ?? 0);
  const levelChanged = previousLevel !== level;
  const publicationStale = nowMillis - lastPublishedAtMillis >= policy.publishIntervalMs;
  const previouslyBlockedCollections = Object.entries(policy.recordLimits)
    .filter(([collectionId, limit]) => (previous?.activeRecords[collectionId] ?? 0) >= limit)
    .map(([collectionId]) => collectionId)
    .sort();
  const blockedCollectionsChanged = blockedCollections.length !== previouslyBlockedCollections.length
    || blockedCollections.some((collectionId, index) => collectionId !== previouslyBlockedCollections[index]);
  const shouldPublish = previous === null || levelChanged || publicationStale || blockedCollectionsChanged;

  return {
    activeRecords,
    blockedCollections,
    dailyWrites,
    dayKey,
    lastPublishedAtMillis: shouldPublish ? nowMillis : lastPublishedAtMillis,
    level,
    limitedUntilMillis,
    message,
    publishedLevel: shouldPublish ? level : previousLevel,
    shouldPublish,
    velocityWrites,
    windowKey,
    writesAllowed
  };
}

function finiteNumber(value: unknown): number | null {
  const candidate = typeof value === "number"
    ? value
    : typeof value === "string" && value.trim()
      ? Number(value)
      : Number.NaN;
  return Number.isFinite(candidate) && candidate >= 0 ? candidate : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
