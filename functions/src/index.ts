import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  Environment,
  SignedDataVerifier
} from "@apple/app-store-server-library";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onMessagePublished } from "firebase-functions/v2/pubsub";
import {
  CREATE_TEAM_RATE_LIMIT,
  evaluateFixedWindowRateLimit,
  evaluateTeamBudgetAlert,
  evaluateTeamUsage,
  FixedWindowRateLimitPolicy,
  FixedWindowRateLimitState,
  METERED_TEAM_COLLECTIONS,
  SYNC_ENTITLEMENT_RATE_LIMIT,
  TEAM_BUDGET_TOPIC,
  TEAM_OPERATIONS_CONTROL_COLLECTION,
  TEAM_OPERATIONS_CONTROL_DOCUMENT,
  TEAM_OPERATIONS_PAUSED_MESSAGE,
  TEAM_USAGE_CONTROL_COLLECTION,
  TEAM_USAGE_COUNTER_COLLECTION,
  TEAM_USAGE_EVENT_COLLECTION,
  TEAM_USAGE_EVENT_RETENTION_MS,
  TEAM_USAGE_POLICY,
  TeamUsageCounterState,
  TeamUsageDecision,
  TeamUsageLevel
} from "./costControl";
import {
  AppStoreTeamTransaction,
  cleanOptionalText,
  cleanRequiredText,
  deriveTeamEntitlementState,
  normalizeTeamTransaction,
  NormalizedTeamTransaction,
  teamAppAccountTokenForUser,
  TEAM_MEMBER_LIMIT
} from "./teamEntitlement";

initializeApp();
const TEAM_RUNTIME_SERVICE_ACCOUNT = "d2d-team-runtime@d2d-advancer.iam.gserviceaccount.com";
setGlobalOptions({
  cpu: "gcf_gen1",
  maxInstances: 3,
  memory: "256MiB",
  minInstances: 0,
  region: "us-central1",
  serviceAccount: TEAM_RUNTIME_SERVICE_ACCOUNT,
  timeoutSeconds: 30
});

const APPLE_APP_ID = 6751178741;
const APPLE_BUNDLE_ID = "dan1sland.D2D-Advancer";

const TEAM_SCHEMA_VERSION = 2;
const TEAM_APP_CHECK_ENFORCED = process.env.D2D_ENFORCE_TEAM_APP_CHECK === "true"
  && process.env.FUNCTIONS_EMULATOR !== "true";
const TEAM_CALLABLE_OPTIONS = {
  enforceAppCheck: TEAM_APP_CHECK_ENFORCED
};
const ROOT_CERTIFICATE_FILES = [
  "AppleIncRootCertificate.cer",
  "AppleRootCA-G2.cer",
  "AppleRootCA-G3.cer"
];

let cachedRootCertificates: Buffer[] | null = null;

function rootCertificates(): Buffer[] {
  if (cachedRootCertificates === null) {
    cachedRootCertificates = ROOT_CERTIFICATE_FILES.map((fileName) =>
      readFileSync(join(__dirname, "..", "certs", fileName))
    );
  }
  return cachedRootCertificates;
}

function untrustedEnvironment(signedPayload: string): Environment | null {
  try {
    const components = signedPayload.split(".");
    if (components.length !== 3) {
      return null;
    }
    const payload = JSON.parse(Buffer.from(components[1], "base64url").toString("utf8")) as {
      data?: { environment?: string };
      environment?: string;
    };
    const raw = payload.environment ?? payload.data?.environment;
    if (raw?.toLowerCase() === "production") {
      return Environment.PRODUCTION;
    }
    if (raw?.toLowerCase() === "sandbox") {
      return Environment.SANDBOX;
    }
  } catch {
    // The hint is never trusted; full signature verification happens below.
  }
  return null;
}

function verifier(environment: Environment): SignedDataVerifier {
  const appAppleId = environment === Environment.PRODUCTION
    ? APPLE_APP_ID
    : undefined;
  return new SignedDataVerifier(
    rootCertificates(),
    true,
    environment,
    APPLE_BUNDLE_ID,
    appAppleId
  );
}

async function verifyTransactionJWS(signedTransaction: string): Promise<NormalizedTeamTransaction> {
  const hintedEnvironment = untrustedEnvironment(signedTransaction);
  const environments = hintedEnvironment
    ? [hintedEnvironment]
    : [Environment.PRODUCTION, Environment.SANDBOX];
  let lastError: unknown;

  for (const environment of environments) {
    try {
      const decoded = await verifier(environment).verifyAndDecodeTransaction(signedTransaction);
      return normalizeTeamTransaction(decoded as AppStoreTeamTransaction);
    } catch (error) {
      lastError = error;
    }
  }

  logger.warn("App Store Team transaction verification failed", { error: String(lastError) });
  throw new HttpsError("failed-precondition", "The Team purchase could not be verified with Apple.");
}

async function verifyNotificationJWS(signedPayload: string): Promise<{
  signedTransactionInfo?: string;
}> {
  const hintedEnvironment = untrustedEnvironment(signedPayload);
  const environments = hintedEnvironment
    ? [hintedEnvironment]
    : [Environment.PRODUCTION, Environment.SANDBOX];
  let lastError: unknown;

  for (const environment of environments) {
    try {
      const decoded = await verifier(environment).verifyAndDecodeNotification(signedPayload);
      return {
        signedTransactionInfo: decoded.data?.signedTransactionInfo
      };
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError ?? new Error("App Store notification verification failed");
}

function requireSignedTransaction(value: unknown): string {
  if (typeof value !== "string" || value.length < 100 || value.length > 100_000) {
    throw new HttpsError("invalid-argument", "A signed App Store transaction is required.");
  }
  return value;
}

function emulatorTeamTransaction(ownerUserId: string, value: unknown): NormalizedTeamTransaction | null {
  if (process.env.FUNCTIONS_EMULATOR !== "true" || value !== "D2D_EMULATOR_TEAM_ENTITLEMENT") {
    return null;
  }

  const safeOwnerId = ownerUserId.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 120);
  const expiresAtMillis = Date.now() + 365 * 24 * 60 * 60 * 1_000;
  return {
    appAccountToken: teamAppAccountTokenForUser(ownerUserId),
    environment: "LocalTesting",
    expiresAtMillis,
    originalTransactionId: `emulator-original-${safeOwnerId}`,
    productId: "com.d2dadvancer.team3.yearly",
    transactionId: `emulator-transaction-${safeOwnerId}`
  };
}

function assertPurchaseBelongsToOwner(
  ownerUserId: string,
  transaction: NormalizedTeamTransaction
): void {
  if (transaction.appAccountToken.toLowerCase() !== teamAppAccountTokenForUser(ownerUserId)) {
    throw new HttpsError("permission-denied", "This Team purchase belongs to another account.");
  }
}

function assertSafeDocumentId(value: string): void {
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(value)) {
    throw new HttpsError("failed-precondition", "The App Store transaction identifier is invalid.");
  }
}

function entitlementData(
  ownerUserId: string,
  transaction: NormalizedTeamTransaction,
  now: Date
): Record<string, unknown> {
  const state = deriveTeamEntitlementState(transaction, now.getTime());
  return {
    appAccountToken: transaction.appAccountToken,
    environment: transaction.environment,
    expiresAt: Timestamp.fromMillis(transaction.expiresAtMillis),
    graceEndsAt: Timestamp.fromMillis(state.graceEndsAtMillis),
    memberLimit: TEAM_MEMBER_LIMIT,
    originalTransactionId: transaction.originalTransactionId,
    ownerUserId,
    planStatus: state.planStatus,
    productId: transaction.productId,
    schemaVersion: TEAM_SCHEMA_VERSION,
    source: "app_store",
    transactionId: transaction.transactionId,
    updatedAt: Timestamp.fromDate(now),
    verifiedAt: Timestamp.fromDate(now)
  };
}

function teamPlanData(
  transaction: NormalizedTeamTransaction,
  now: Date
): Record<string, unknown> {
  const state = deriveTeamEntitlementState(transaction, now.getTime());
  return {
    billingOriginalTransactionId: transaction.originalTransactionId,
    billingProductId: transaction.productId,
    billingSource: "app_store",
    graceEndsAt: Timestamp.fromMillis(state.graceEndsAtMillis),
    planExpiresAt: Timestamp.fromMillis(transaction.expiresAtMillis),
    planStatus: state.planStatus,
    schemaVersion: TEAM_SCHEMA_VERSION,
    updatedAt: Timestamp.fromDate(now)
  };
}

function validatePurchaseBinding(
  ownerUserId: string,
  bindingOwnerUserId: unknown,
  accountOwnerUserId: unknown
): void {
  if (typeof bindingOwnerUserId === "string" && bindingOwnerUserId !== ownerUserId) {
    throw new HttpsError("permission-denied", "This Team subscription is already linked to another account.");
  }
  if (typeof accountOwnerUserId === "string" && accountOwnerUserId !== ownerUserId) {
    throw new HttpsError("permission-denied", "This Team purchase belongs to another account.");
  }
}

function teamOperationsControlRef() {
  return getFirestore()
    .collection(TEAM_OPERATIONS_CONTROL_COLLECTION)
    .doc(TEAM_OPERATIONS_CONTROL_DOCUMENT);
}

function teamUsageCounterRef(teamId: string) {
  return getFirestore().collection(TEAM_USAGE_COUNTER_COLLECTION).doc(teamId);
}

function teamUsageControlRef(teamId: string) {
  return getFirestore().collection(TEAM_USAGE_CONTROL_COLLECTION).doc(teamId);
}

function teamUsageCounterFromData(data: Record<string, unknown> | undefined): TeamUsageCounterState | null {
  if (!data) {
    return null;
  }
  const activeRecordsValue = data.activeRecords;
  const activeRecords = typeof activeRecordsValue === "object"
    && activeRecordsValue !== null
    && !Array.isArray(activeRecordsValue)
    ? Object.fromEntries(
      Object.entries(activeRecordsValue).map(([key, value]) => [
        key,
        typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : 0
      ])
    )
    : {};
  const lastPublishedAtMillis = data.lastPublishedAt instanceof Timestamp
    ? data.lastPublishedAt.toMillis()
    : 0;
  const publishedLevel: TeamUsageLevel = data.publishedLevel === "warning"
    || data.publishedLevel === "limited"
    ? data.publishedLevel
    : "normal";

  return {
    activeRecords,
    dailyWrites: typeof data.dailyWrites === "number" ? Math.max(0, Math.trunc(data.dailyWrites)) : 0,
    dayKey: typeof data.dayKey === "string" ? data.dayKey : "",
    lastPublishedAtMillis,
    publishedLevel,
    velocityWrites: typeof data.velocityWrites === "number"
      ? Math.max(0, Math.trunc(data.velocityWrites))
      : 0,
    windowKey: typeof data.windowKey === "string" ? data.windowKey : ""
  };
}

function teamUsageCounterData(
  teamId: string,
  decision: TeamUsageDecision,
  now: Timestamp
): Record<string, unknown> {
  return {
    activeRecords: decision.activeRecords,
    dailyWrites: decision.dailyWrites,
    dayKey: decision.dayKey,
    lastPublishedAt: Timestamp.fromMillis(decision.lastPublishedAtMillis),
    publishedLevel: decision.publishedLevel,
    teamId,
    updatedAt: now,
    velocityWrites: decision.velocityWrites,
    windowKey: decision.windowKey
  };
}

function teamUsageControlData(
  teamId: string,
  decision: TeamUsageDecision,
  now: Timestamp
): Record<string, unknown> {
  return {
    activeRecords: decision.activeRecords,
    blockedCollections: decision.blockedCollections,
    dailyWriteLimit: TEAM_USAGE_POLICY.dailyWriteLimit,
    dailyWrites: decision.dailyWrites,
    level: decision.level,
    limitedUntil: decision.limitedUntilMillis === null
      ? null
      : Timestamp.fromMillis(decision.limitedUntilMillis),
    message: decision.message,
    recordLimits: TEAM_USAGE_POLICY.recordLimits,
    teamId,
    updatedAt: now,
    velocityWindowMinutes: TEAM_USAGE_POLICY.velocityWindowMs / 60_000,
    velocityWriteLimit: TEAM_USAGE_POLICY.velocityWriteLimit,
    velocityWrites: decision.velocityWrites,
    writesAllowed: decision.writesAllowed
  };
}

function initialTeamUsageDecision(nowMillis: number): TeamUsageDecision {
  const first = evaluateTeamUsage(null, { collectionId: "members", recordDelta: 0 }, nowMillis);
  return {
    ...first,
    dailyWrites: 0,
    velocityWrites: 0
  };
}

function assertTeamOperationsDataAllowsWrite(data: Record<string, unknown> | undefined): void {
  if (data !== undefined && data.teamWritesEnabled !== true) {
    const message = typeof data.message === "string" && data.message.trim()
      ? data.message.trim().slice(0, 240)
      : TEAM_OPERATIONS_PAUSED_MESSAGE;
    throw new HttpsError("unavailable", message);
  }
}

async function assertTeamOperationsAllowWrite(): Promise<void> {
  const snapshot = await teamOperationsControlRef().get();
  assertTeamOperationsDataAllowsWrite(snapshot.data());
}

async function enforceUserRateLimit(
  userId: string,
  action: string,
  policy: FixedWindowRateLimitPolicy
): Promise<void> {
  const db = getFirestore();
  const userHash = createHash("sha256").update(userId).digest("hex").slice(0, 40);
  const ref = db.collection("serverRateLimits").doc(`${action}-${userHash}`);
  const nowMillis = Date.now();

  await db.runTransaction(async (firestoreTransaction) => {
    const snapshot = await firestoreTransaction.get(ref);
    const data = snapshot.data();
    const windowStartedAt = data?.windowStartedAt instanceof Timestamp
      ? data.windowStartedAt.toMillis()
      : null;
    const count = typeof data?.count === "number" ? data.count : null;
    const previous: FixedWindowRateLimitState | null = windowStartedAt !== null && count !== null
      ? { count, windowStartedAtMillis: windowStartedAt }
      : null;
    const decision = evaluateFixedWindowRateLimit(previous, nowMillis, policy);

    if (!decision.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        `Too many requests. Try again in about ${decision.retryAfterSeconds} seconds.`
      );
    }

    firestoreTransaction.set(ref, {
      action,
      count: decision.count,
      expiresAt: Timestamp.fromMillis(decision.windowStartedAtMillis + policy.windowMs * 2),
      updatedAt: Timestamp.fromMillis(nowMillis),
      windowStartedAt: Timestamp.fromMillis(decision.windowStartedAtMillis)
    });
  });
}

async function syncEntitlementForOwner(
  ownerUserId: string,
  transaction: NormalizedTeamTransaction
): Promise<{ planStatus: string; teamId: string | null }> {
  assertPurchaseBelongsToOwner(ownerUserId, transaction);
  assertSafeDocumentId(transaction.originalTransactionId);
  assertSafeDocumentId(transaction.appAccountToken);

  const db = getFirestore();
  const now = new Date();
  const bindingRef = db.collection("teamSubscriptionTransactions").doc(transaction.originalTransactionId);
  const accountRef = db.collection("teamBillingAccounts").doc(transaction.appAccountToken);
  const entitlementRef = db.collection("teamEntitlements").doc(ownerUserId);
  const profileRef = db.collection("users").doc(ownerUserId).collection("teamProfile").doc("current");
  const state = deriveTeamEntitlementState(transaction, now.getTime());

  return db.runTransaction(async (firestoreTransaction) => {
    const bindingSnapshot = await firestoreTransaction.get(bindingRef);
    const accountSnapshot = await firestoreTransaction.get(accountRef);
    const profileSnapshot = await firestoreTransaction.get(profileRef);

    validatePurchaseBinding(
      ownerUserId,
      bindingSnapshot.data()?.ownerUserId,
      accountSnapshot.data()?.ownerUserId
    );

    const profile = profileSnapshot.data();
    const teamId = profile?.role === "owner" && typeof profile.teamId === "string"
      ? profile.teamId
      : null;
    const teamRef = teamId ? db.collection("teams").doc(teamId) : null;
    const ownerMemberRef = teamRef ? teamRef.collection("members").doc(ownerUserId) : null;
    const teamSnapshot = teamRef ? await firestoreTransaction.get(teamRef) : null;
    const ownerMemberSnapshot = ownerMemberRef
      ? await firestoreTransaction.get(ownerMemberRef)
      : null;

    firestoreTransaction.set(bindingRef, {
      appAccountToken: transaction.appAccountToken,
      environment: transaction.environment,
      latestTransactionId: transaction.transactionId,
      ownerUserId,
      productId: transaction.productId,
      updatedAt: Timestamp.fromDate(now)
    }, { merge: true });
    firestoreTransaction.set(accountRef, {
      originalTransactionId: transaction.originalTransactionId,
      ownerUserId,
      updatedAt: Timestamp.fromDate(now)
    }, { merge: true });
    firestoreTransaction.set(
      entitlementRef,
      entitlementData(ownerUserId, transaction, now),
      { merge: true }
    );

    if (
      teamRef
      && teamSnapshot?.exists
      && teamSnapshot.data()?.ownerUserId === ownerUserId
      && ownerMemberSnapshot?.data()?.status === "active"
    ) {
      firestoreTransaction.update(teamRef, teamPlanData(transaction, now));
    }

    return { planStatus: state.planStatus, teamId };
  });
}

export const syncTeamEntitlement = onCall(TEAM_CALLABLE_OPTIONS, async (request) => {
  const ownerUserId = request.auth?.uid;
  if (!ownerUserId) {
    throw new HttpsError("unauthenticated", "Sign in with Apple before checking Team access.");
  }

  await assertTeamOperationsAllowWrite();
  await enforceUserRateLimit(ownerUserId, "sync-entitlement", SYNC_ENTITLEMENT_RATE_LIMIT);

  const transaction = emulatorTeamTransaction(ownerUserId, request.data?.signedTransaction)
    ?? await verifyTransactionJWS(requireSignedTransaction(request.data?.signedTransaction));
  return syncEntitlementForOwner(ownerUserId, transaction);
});

export const createTeamWorkspace = onCall(TEAM_CALLABLE_OPTIONS, async (request) => {
  const ownerUserId = request.auth?.uid;
  if (!ownerUserId) {
    throw new HttpsError("unauthenticated", "Sign in with Apple before creating a team.");
  }

  await assertTeamOperationsAllowWrite();
  await enforceUserRateLimit(ownerUserId, "create-team", CREATE_TEAM_RATE_LIMIT);

  const verifiedTransaction = emulatorTeamTransaction(ownerUserId, request.data?.signedTransaction)
    ?? await verifyTransactionJWS(requireSignedTransaction(request.data?.signedTransaction));
  assertPurchaseBelongsToOwner(ownerUserId, verifiedTransaction);
  const now = new Date();
  const state = deriveTeamEntitlementState(verifiedTransaction, now.getTime());
  if (state.planStatus !== "active") {
    throw new HttpsError("failed-precondition", "Renew the Team plan before creating a workspace.");
  }

  assertSafeDocumentId(verifiedTransaction.originalTransactionId);
  assertSafeDocumentId(verifiedTransaction.appAccountToken);

  const teamName = cleanRequiredText(request.data?.name, "My Team", 80);
  const displayName = cleanRequiredText(request.data?.displayName, "Team Owner", 80);
  const email = cleanOptionalText(request.data?.email, 254);
  const teamId = randomUUID();
  const activityId = randomUUID();
  const db = getFirestore();
  const teamRef = db.collection("teams").doc(teamId);
  const ownerMemberRef = teamRef.collection("members").doc(ownerUserId);
  const profileRef = db.collection("users").doc(ownerUserId).collection("teamProfile").doc("current");
  const bindingRef = db.collection("teamSubscriptionTransactions").doc(verifiedTransaction.originalTransactionId);
  const accountRef = db.collection("teamBillingAccounts").doc(verifiedTransaction.appAccountToken);
  const entitlementRef = db.collection("teamEntitlements").doc(ownerUserId);
  const usageCounterRef = teamUsageCounterRef(teamId);
  const usageControlRef = teamUsageControlRef(teamId);

  await db.runTransaction(async (firestoreTransaction) => {
    const operationsSnapshot = await firestoreTransaction.get(teamOperationsControlRef());
    const profileSnapshot = await firestoreTransaction.get(profileRef);
    const bindingSnapshot = await firestoreTransaction.get(bindingRef);
    const accountSnapshot = await firestoreTransaction.get(accountRef);

    assertTeamOperationsDataAllowsWrite(operationsSnapshot.data());

    if (profileSnapshot.exists) {
      throw new HttpsError("already-exists", "This account is already in a team.");
    }
    validatePurchaseBinding(
      ownerUserId,
      bindingSnapshot.data()?.ownerUserId,
      accountSnapshot.data()?.ownerUserId
    );

    const timestamp = Timestamp.fromDate(now);
    const initialUsage = initialTeamUsageDecision(now.getTime());
    firestoreTransaction.set(bindingRef, {
      appAccountToken: verifiedTransaction.appAccountToken,
      environment: verifiedTransaction.environment,
      latestTransactionId: verifiedTransaction.transactionId,
      ownerUserId,
      productId: verifiedTransaction.productId,
      updatedAt: timestamp
    }, { merge: true });
    firestoreTransaction.set(accountRef, {
      originalTransactionId: verifiedTransaction.originalTransactionId,
      ownerUserId,
      updatedAt: timestamp
    }, { merge: true });
    firestoreTransaction.set(
      entitlementRef,
      entitlementData(ownerUserId, verifiedTransaction, now),
      { merge: true }
    );
    firestoreTransaction.set(teamRef, {
      ...teamPlanData(verifiedTransaction, now),
      createdAt: timestamp,
      memberLimit: TEAM_MEMBER_LIMIT,
      name: teamName,
      ownerUserId
    });
    firestoreTransaction.set(ownerMemberRef, {
      displayName,
      ...(email ? { email } : {}),
      joinedAt: timestamp,
      role: "owner",
      status: "active",
      teamId,
      updatedAt: timestamp,
      userId: ownerUserId,
      workType: "owner"
    });
    firestoreTransaction.set(profileRef, {
      role: "owner",
      teamId,
      updatedAt: timestamp
    });
    firestoreTransaction.set(teamRef.collection("activityLog").doc(activityId), {
      actorDisplayName: displayName,
      actorUserId: ownerUserId,
      createdAt: timestamp,
      kind: "team_created",
      subjectId: teamId,
      subjectTitle: teamName,
      targetUserId: ownerUserId,
      teamId
    });
    firestoreTransaction.set(
      usageCounterRef,
      teamUsageCounterData(teamId, initialUsage, timestamp)
    );
    firestoreTransaction.set(
      usageControlRef,
      teamUsageControlData(teamId, initialUsage, timestamp)
    );
  });

  return {
    memberLimit: TEAM_MEMBER_LIMIT,
    planStatus: state.planStatus,
    teamId
  };
});

export const meterTeamUsage = onDocumentWritten({
  document: "teams/{teamId}/{collectionId}/{documentId}",
  retry: true
}, async (event) => {
  const change = event.data;
  const teamId = event.params.teamId;
  const collectionId = event.params.collectionId;
  if (!change || typeof teamId !== "string" || !METERED_TEAM_COLLECTIONS.has(collectionId)) {
    return;
  }

  const existedBefore = change.before.exists;
  const existsAfter = change.after.exists;
  const recordDelta = existedBefore === existsAfter ? 0 : existsAfter ? 1 : -1;
  const eventId = createHash("sha256")
    .update(event.id)
    .digest("hex");
  const db = getFirestore();
  const eventRef = db.collection(TEAM_USAGE_EVENT_COLLECTION).doc(eventId);
  const counterRef = teamUsageCounterRef(teamId);
  const controlRef = teamUsageControlRef(teamId);
  const nowMillis = Date.now();
  const now = Timestamp.fromMillis(nowMillis);

  const publishedDecision = await db.runTransaction<TeamUsageDecision | null>(async (firestoreTransaction) => {
    const eventSnapshot = await firestoreTransaction.get(eventRef);
    if (eventSnapshot.exists) {
      return null;
    }
    const counterSnapshot = await firestoreTransaction.get(counterRef);
    const decision = evaluateTeamUsage(
      teamUsageCounterFromData(counterSnapshot.data()),
      { collectionId, recordDelta },
      nowMillis
    );

    firestoreTransaction.create(eventRef, {
      collectionId,
      eventId: event.id,
      expiresAt: Timestamp.fromMillis(nowMillis + TEAM_USAGE_EVENT_RETENTION_MS),
      processedAt: now,
      teamId
    });
    firestoreTransaction.set(
      counterRef,
      teamUsageCounterData(teamId, decision, now)
    );
    if (decision.shouldPublish) {
      firestoreTransaction.set(
        controlRef,
        teamUsageControlData(teamId, decision, now)
      );
      return decision;
    }
    return null;
  });

  if (publishedDecision?.level === "limited") {
    logger.error("Team usage limiter paused writes", {
      dailyWrites: publishedDecision.dailyWrites,
      limitedUntilMillis: publishedDecision.limitedUntilMillis,
      teamId,
      velocityWrites: publishedDecision.velocityWrites
    });
  } else if (publishedDecision?.level === "warning") {
    logger.warn("Team usage is approaching an included limit", {
      blockedCollections: publishedDecision.blockedCollections,
      dailyWrites: publishedDecision.dailyWrites,
      teamId,
      velocityWrites: publishedDecision.velocityWrites
    });
  }
});

async function applyNotificationTransaction(
  transaction: NormalizedTeamTransaction
): Promise<void> {
  assertSafeDocumentId(transaction.originalTransactionId);

  const db = getFirestore();
  const bindingRef = db.collection("teamSubscriptionTransactions").doc(transaction.originalTransactionId);
  const bindingSnapshot = await bindingRef.get();
  const ownerUserId = bindingSnapshot.data()?.ownerUserId;
  if (typeof ownerUserId !== "string") {
    logger.info("Ignoring an unbound Team subscription notification", {
      originalTransactionId: transaction.originalTransactionId
    });
    return;
  }

  await syncEntitlementForOwner(ownerUserId, transaction);
}

export const appStoreServerNotifications = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).send("Method not allowed");
    return;
  }

  const signedPayload = request.body?.signedPayload;
  if (typeof signedPayload !== "string" || signedPayload.length < 100 || signedPayload.length > 500_000) {
    response.status(400).send("Invalid signedPayload");
    return;
  }

  try {
    const notification = await verifyNotificationJWS(signedPayload);
    if (notification.signedTransactionInfo) {
      const transaction = await verifyTransactionJWS(notification.signedTransactionInfo);
      await applyNotificationTransaction(transaction);
    }
    response.status(200).send("OK");
  } catch (error) {
    logger.error("App Store Server Notification processing failed", { error: String(error) });
    response.status(500).send("Notification could not be verified");
  }
});

// Keep the original HTTPS resource private while the budget listener moves to Pub/Sub.
export const pauseTeamWritesOnBudget = onRequest({
  invoker: "private",
  maxInstances: 1
}, (_request, response) => {
  response.status(410).send("Budget alerts are handled by pauseTeamWritesOnBudgetAlert.");
});

export const pauseTeamWritesOnBudgetAlert = onMessagePublished({
  maxInstances: 1,
  retry: false,
  topic: TEAM_BUDGET_TOPIC
}, async (event) => {
  let payload: unknown;
  try {
    payload = event.data.message.json;
  } catch (error) {
    logger.warn("Ignoring an unreadable Cloud Billing budget message", { error: String(error) });
    return;
  }

  const decision = evaluateTeamBudgetAlert(payload);
  if (!decision.shouldPauseTeamWrites) {
    logger.info("Cloud Billing budget message is below the Team write-lock threshold", {
      alertThreshold: decision.alertThreshold,
      budgetAmount: decision.budgetAmount,
      costAmount: decision.costAmount,
      costRatio: decision.costRatio
    });
    return;
  }

  const db = getFirestore();
  const controlRef = teamOperationsControlRef();
  const now = Timestamp.now();
  const didPause = await db.runTransaction(async (firestoreTransaction) => {
    const snapshot = await firestoreTransaction.get(controlRef);
    if (snapshot.data()?.teamWritesEnabled === false) {
      return false;
    }

    firestoreTransaction.set(controlRef, {
      alertThreshold: decision.alertThreshold,
      budgetAmount: decision.budgetAmount,
      costAmount: decision.costAmount,
      costRatio: decision.costRatio,
      currencyCode: decision.currencyCode,
      message: TEAM_OPERATIONS_PAUSED_MESSAGE,
      notificationId: event.id,
      pausedAt: now,
      reason: "budget_threshold",
      source: "cloud_billing_budget",
      teamWritesEnabled: false,
      updatedAt: now
    }, { merge: true });
    return true;
  });

  logger.warn(didPause
    ? "Team writes were paused after a Cloud Billing budget alert"
    : "Team writes were already paused when a Cloud Billing budget alert arrived", {
    alertThreshold: decision.alertThreshold,
    budgetAmount: decision.budgetAmount,
    costAmount: decision.costAmount,
    costRatio: decision.costRatio,
    notificationId: event.id
  });
});
