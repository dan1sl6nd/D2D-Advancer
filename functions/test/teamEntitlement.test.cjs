const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const {
  cleanOptionalText,
  cleanRequiredText,
  deriveTeamEntitlementState,
  normalizeTeamTransaction,
  shouldApplyTeamTransaction,
  teamAppAccountTokenForUser,
  TEAM_GRACE_PERIOD_MS
} = require("../lib/teamEntitlement.js");

const now = Date.UTC(2026, 6, 12, 12, 0, 0);

describe("Team entitlement migration policy", () => {
  it("keeps a current Team subscription writable", () => {
    const state = deriveTeamEntitlementState({ expiresAtMillis: now + 60_000 }, now);
    assert.equal(state.planStatus, "active");
    assert.equal(state.graceEndsAtMillis, now + 60_000 + TEAM_GRACE_PERIOD_MS);
  });

  it("moves an expired Team subscription into seven-day read-only grace", () => {
    const state = deriveTeamEntitlementState({ expiresAtMillis: now - 60_000 }, now);
    assert.equal(state.planStatus, "grace");
  });

  it("pauses Team after grace and immediately after revocation", () => {
    assert.equal(
      deriveTeamEntitlementState({ expiresAtMillis: now - TEAM_GRACE_PERIOD_MS - 1 }, now).planStatus,
      "paused"
    );
    assert.equal(
      deriveTeamEntitlementState({ expiresAtMillis: now + 60_000, revocationAtMillis: now }, now).planStatus,
      "paused"
    );
  });

  it("accepts only linked Team products", () => {
    const normalized = normalizeTeamTransaction({
      appAccountToken: "0d111c55-7c4d-4f56-8c73-04aa7ef3c2a1",
      environment: "Sandbox",
      expiresDate: now + 60_000,
      originalTransactionId: "1000000001",
      productId: "com.d2dadvancer.team3.yearly",
      signedDate: now,
      transactionId: "1000000002"
    });
    assert.equal(normalized.productId, "com.d2dadvancer.team3.yearly");
    assert.equal(normalized.signedAtMillis, now);

    const legacyTeam = normalizeTeamTransaction({
      appAccountToken: "0d111c55-7c4d-4f56-8c73-04aa7ef3c2a1",
      environment: "Sandbox",
      expiresDate: now + 60_000,
      originalTransactionId: "1000000003",
      productId: "com.d2dadvancer.team.yearly",
      signedDate: now,
      transactionId: "1000000004"
    });
    assert.equal(legacyTeam.productId, "com.d2dadvancer.team.yearly");

    assert.throws(() => normalizeTeamTransaction({
      appAccountToken: "0d111c55-7c4d-4f56-8c73-04aa7ef3c2a1",
      environment: "Sandbox",
      expiresDate: now + 60_000,
      originalTransactionId: "1000000001",
      productId: "com.d2dadvancer.yearly",
      transactionId: "1000000002"
    }));
  });

  it("never lets an older renewal overwrite the current Team entitlement", () => {
    const newest = normalizeTeamTransaction({
      appAccountToken: "0d111c55-7c4d-4f56-8c73-04aa7ef3c2a1",
      environment: "Production",
      expiresDate: now + 60_000,
      originalTransactionId: "1000000001",
      productId: "com.d2dadvancer.team3.monthly",
      signedDate: now,
      transactionId: "1000000003"
    });
    const existing = {
      expiresAtMillis: newest.expiresAtMillis,
      signedAtMillis: newest.signedAtMillis,
      transactionId: newest.transactionId
    };
    const stale = {
      ...newest,
      expiresAtMillis: now - 60_000,
      signedAtMillis: now + 1_000,
      transactionId: "1000000002"
    };

    assert.equal(shouldApplyTeamTransaction(existing, stale), false);
  });

  it("accepts renewals and newer revocations but rejects stale unrevoked copies", () => {
    const base = normalizeTeamTransaction({
      appAccountToken: "0d111c55-7c4d-4f56-8c73-04aa7ef3c2a1",
      environment: "Production",
      expiresDate: now + 60_000,
      originalTransactionId: "1000000001",
      productId: "com.d2dadvancer.team3.yearly",
      signedDate: now,
      transactionId: "1000000002"
    });
    const existing = {
      expiresAtMillis: base.expiresAtMillis,
      signedAtMillis: base.signedAtMillis,
      transactionId: base.transactionId
    };
    const renewal = {
      ...base,
      expiresAtMillis: now + 120_000,
      signedAtMillis: now + 1_000,
      transactionId: "1000000003"
    };
    const revocation = {
      ...base,
      revocationAtMillis: now + 500,
      signedAtMillis: now + 1_000
    };

    assert.equal(shouldApplyTeamTransaction(existing, renewal), true);
    assert.equal(shouldApplyTeamTransaction(existing, revocation), true);
    assert.equal(shouldApplyTeamTransaction({ ...existing, revocationAtMillis: now }, base), false);
  });

  it("derives the same stable owner token as the iOS client", () => {
    assert.equal(
      teamAppAccountTokenForUser("owner-1"),
      "5dea72f7-ed61-55f2-b315-9dfefbbffd78"
    );
    assert.notEqual(
      teamAppAccountTokenForUser("owner-1"),
      teamAppAccountTokenForUser("owner-2")
    );
  });

  it("normalizes user-entered team identity fields", () => {
    assert.equal(cleanRequiredText("  North   Crew  ", "My Team", 80), "North Crew");
    assert.equal(cleanRequiredText("   ", "My Team", 80), "My Team");
    assert.equal(cleanOptionalText("  owner@example.com ", 254), "owner@example.com");
    assert.equal(cleanOptionalText("   ", 254), null);
  });
});
