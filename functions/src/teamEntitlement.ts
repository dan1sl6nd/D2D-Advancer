import { createHash } from "node:crypto";

export const TEAM_MEMBER_LIMIT = 3;
export const TEAM_GRACE_PERIOD_MS = 7 * 24 * 60 * 60 * 1_000;

export const TEAM_PRODUCT_IDS = new Set([
  "com.d2dadvancer.team.monthly",
  "com.d2dadvancer.team.yearly",
  "com.d2dadvancer.team3.monthly",
  "com.d2dadvancer.team3.yearly"
]);

export type TeamPlanStatus = "active" | "grace" | "paused";

export interface AppStoreTeamTransaction {
  appAccountToken?: string;
  bundleId?: string;
  environment?: string;
  expiresDate?: number;
  originalTransactionId?: string;
  productId?: string;
  revocationDate?: number;
  transactionId?: string;
}

export interface NormalizedTeamTransaction {
  appAccountToken: string;
  environment: string;
  expiresAtMillis: number;
  originalTransactionId: string;
  productId: string;
  revocationAtMillis?: number;
  transactionId: string;
}

export interface TeamEntitlementState {
  graceEndsAtMillis: number;
  planStatus: TeamPlanStatus;
}

export function teamAppAccountTokenForUser(ownerUserId: string): string {
  const bytes = Buffer.from(
    createHash("sha256").update(`d2d-team:${ownerUserId}`, "utf8").digest().subarray(0, 16)
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  const hex = bytes.toString("hex");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20)
  ].join("-");
}

export function normalizeTeamTransaction(
  transaction: AppStoreTeamTransaction
): NormalizedTeamTransaction {
  if (!transaction.productId || !TEAM_PRODUCT_IDS.has(transaction.productId)) {
    throw new Error("A current Team subscription is required.");
  }
  if (!transaction.originalTransactionId || !transaction.transactionId) {
    throw new Error("The App Store transaction is missing an identifier.");
  }
  if (!transaction.appAccountToken) {
    throw new Error("The Team purchase is not linked to this account.");
  }
  if (!transaction.environment) {
    throw new Error("The App Store transaction is missing its environment.");
  }
  if (!Number.isFinite(transaction.expiresDate)) {
    throw new Error("The Team subscription is missing an expiration date.");
  }

  return {
    appAccountToken: transaction.appAccountToken,
    environment: transaction.environment,
    expiresAtMillis: transaction.expiresDate as number,
    originalTransactionId: transaction.originalTransactionId,
    productId: transaction.productId,
    revocationAtMillis: Number.isFinite(transaction.revocationDate)
      ? transaction.revocationDate
      : undefined,
    transactionId: transaction.transactionId
  };
}

export function deriveTeamEntitlementState(
  transaction: Pick<NormalizedTeamTransaction, "expiresAtMillis" | "revocationAtMillis">,
  nowMillis: number = Date.now()
): TeamEntitlementState {
  const graceEndsAtMillis = transaction.expiresAtMillis + TEAM_GRACE_PERIOD_MS;

  if (
    transaction.revocationAtMillis !== undefined
    && transaction.revocationAtMillis <= nowMillis
  ) {
    return { graceEndsAtMillis, planStatus: "paused" };
  }
  if (transaction.expiresAtMillis > nowMillis) {
    return { graceEndsAtMillis, planStatus: "active" };
  }
  if (graceEndsAtMillis > nowMillis) {
    return { graceEndsAtMillis, planStatus: "grace" };
  }
  return { graceEndsAtMillis, planStatus: "paused" };
}

export function cleanRequiredText(value: unknown, fallback: string, maxLength: number): string {
  if (typeof value !== "string") {
    return fallback;
  }
  const cleaned = value.trim().replace(/\s+/g, " ");
  return cleaned.length === 0 ? fallback : cleaned.slice(0, maxLength);
}

export function cleanOptionalText(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const cleaned = value.trim().replace(/\s+/g, " ");
  return cleaned.length === 0 ? null : cleaned.slice(0, maxLength);
}
