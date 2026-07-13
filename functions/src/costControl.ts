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

export const CREATE_TEAM_RATE_LIMIT: FixedWindowRateLimitPolicy = {
  maxRequests: 5,
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
