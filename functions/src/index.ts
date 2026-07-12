import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  Environment,
  SignedDataVerifier
} from "@apple/app-store-server-library";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineInt, defineString } from "firebase-functions/params";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import {
  AppStoreTeamTransaction,
  cleanOptionalText,
  cleanRequiredText,
  deriveTeamEntitlementState,
  normalizeTeamTransaction,
  NormalizedTeamTransaction,
  TEAM_MEMBER_LIMIT
} from "./teamEntitlement";

initializeApp();
setGlobalOptions({ maxInstances: 10, region: "us-central1" });

const APPLE_APP_ID = defineInt("APPLE_APP_ID", {
  default: 6738387157,
  description: "Numeric App Store Apple ID for D2D Advancer"
});
const APPLE_BUNDLE_ID = defineString("APPLE_BUNDLE_ID", {
  default: "dan1sland.D2D-Advancer",
  description: "D2D Advancer bundle identifier"
});

const TEAM_SCHEMA_VERSION = 2;
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
    ? APPLE_APP_ID.value()
    : undefined;
  return new SignedDataVerifier(
    rootCertificates(),
    true,
    environment,
    APPLE_BUNDLE_ID.value(),
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
    appAccountToken: `emulator-account-${safeOwnerId}`,
    environment: "LocalTesting",
    expiresAtMillis,
    originalTransactionId: `emulator-original-${safeOwnerId}`,
    productId: "com.d2dadvancer.team.yearly",
    transactionId: `emulator-transaction-${safeOwnerId}`
  };
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

async function syncEntitlementForOwner(
  ownerUserId: string,
  transaction: NormalizedTeamTransaction
): Promise<{ planStatus: string; teamId: string | null }> {
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

export const syncTeamEntitlement = onCall({ timeoutSeconds: 30 }, async (request) => {
  const ownerUserId = request.auth?.uid;
  if (!ownerUserId) {
    throw new HttpsError("unauthenticated", "Sign in with Apple before checking Team access.");
  }

  const transaction = emulatorTeamTransaction(ownerUserId, request.data?.signedTransaction)
    ?? await verifyTransactionJWS(requireSignedTransaction(request.data?.signedTransaction));
  return syncEntitlementForOwner(ownerUserId, transaction);
});

export const createTeamWorkspace = onCall({ timeoutSeconds: 30 }, async (request) => {
  const ownerUserId = request.auth?.uid;
  if (!ownerUserId) {
    throw new HttpsError("unauthenticated", "Sign in with Apple before creating a team.");
  }

  const verifiedTransaction = emulatorTeamTransaction(ownerUserId, request.data?.signedTransaction)
    ?? await verifyTransactionJWS(requireSignedTransaction(request.data?.signedTransaction));
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

  await db.runTransaction(async (firestoreTransaction) => {
    const profileSnapshot = await firestoreTransaction.get(profileRef);
    const bindingSnapshot = await firestoreTransaction.get(bindingRef);
    const accountSnapshot = await firestoreTransaction.get(accountRef);

    if (profileSnapshot.exists) {
      throw new HttpsError("already-exists", "This account is already in a team.");
    }
    validatePurchaseBinding(
      ownerUserId,
      bindingSnapshot.data()?.ownerUserId,
      accountSnapshot.data()?.ownerUserId
    );

    const timestamp = Timestamp.fromDate(now);
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
  });

  return {
    memberLimit: TEAM_MEMBER_LIMIT,
    planStatus: state.planStatus,
    teamId
  };
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

export const appStoreServerNotifications = onRequest({ timeoutSeconds: 30 }, async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).send("Method not allowed");
    return;
  }

  const signedPayload = request.body?.signedPayload;
  if (typeof signedPayload !== "string") {
    response.status(400).send("Missing signedPayload");
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
