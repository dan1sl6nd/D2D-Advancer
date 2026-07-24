const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const {
  CREATE_TEAM_RATE_LIMIT,
  TEAM_BUDGET_LOCK_RATIO,
  TEAM_USAGE_POLICY,
  evaluateFixedWindowRateLimit,
  evaluateTeamBudgetAlert,
  evaluateTeamUsage
} = require("../lib/costControl.js");

describe("cost controls", () => {
  it("starts, increments, blocks, and resets a fixed rate-limit window", () => {
    const started = evaluateFixedWindowRateLimit(null, 1_000, CREATE_TEAM_RATE_LIMIT);
    assert.equal(started.allowed, true);
    assert.equal(started.count, 1);

    let state = started;
    for (let count = 2; count <= CREATE_TEAM_RATE_LIMIT.maxRequests; count += 1) {
      state = evaluateFixedWindowRateLimit(state, 1_000 + count, CREATE_TEAM_RATE_LIMIT);
      assert.equal(state.allowed, true);
      assert.equal(state.count, count);
    }

    const blocked = evaluateFixedWindowRateLimit(state, 2_000, CREATE_TEAM_RATE_LIMIT);
    assert.equal(blocked.allowed, false);
    assert.equal(blocked.count, CREATE_TEAM_RATE_LIMIT.maxRequests);
    assert.ok(blocked.retryAfterSeconds > 0);

    const reset = evaluateFixedWindowRateLimit(
      state,
      1_000 + CREATE_TEAM_RATE_LIMIT.windowMs,
      CREATE_TEAM_RATE_LIMIT
    );
    assert.equal(reset.allowed, true);
    assert.equal(reset.count, 1);
  });

  it("pauses Team writes when either budget ratio or alert threshold reaches 80 percent", () => {
    const ratioDecision = evaluateTeamBudgetAlert({
      budgetAmount: 25,
      costAmount: 20,
      currencyCode: "CAD"
    });
    assert.equal(ratioDecision.costRatio, TEAM_BUDGET_LOCK_RATIO);
    assert.equal(ratioDecision.shouldPauseTeamWrites, true);
    assert.equal(ratioDecision.currencyCode, "CAD");

    const thresholdDecision = evaluateTeamBudgetAlert({
      alertThresholdExceeded: "0.8",
      budgetAmount: 25,
      costAmount: 10
    });
    assert.equal(thresholdDecision.alertThreshold, TEAM_BUDGET_LOCK_RATIO);
    assert.equal(thresholdDecision.shouldPauseTeamWrites, true);
  });

  it("ignores malformed or below-threshold budget messages", () => {
    assert.equal(evaluateTeamBudgetAlert(null).shouldPauseTeamWrites, false);
    assert.equal(evaluateTeamBudgetAlert({ budgetAmount: 0, costAmount: 99 }).shouldPauseTeamWrites, false);
    assert.equal(evaluateTeamBudgetAlert({
      alertThresholdExceeded: 0.5,
      budgetAmount: 25,
      costAmount: 19.99
    }).shouldPauseTeamWrites, false);
  });

  it("meters Team writes across velocity and daily windows", () => {
    const now = Date.parse("2026-07-16T12:00:00.000Z");
    const first = evaluateTeamUsage(null, {
      collectionId: "leads",
      recordDelta: 1
    }, now);

    assert.equal(first.dailyWrites, 1);
    assert.equal(first.velocityWrites, 1);
    assert.equal(first.activeRecords.leads, 1);
    assert.equal(first.level, "normal");
    assert.equal(first.writesAllowed, true);
    assert.equal(first.shouldPublish, true);

    const nextWindow = evaluateTeamUsage(first, {
      collectionId: "leads",
      recordDelta: 0
    }, now + TEAM_USAGE_POLICY.velocityWindowMs);
    assert.equal(nextWindow.dailyWrites, 2);
    assert.equal(nextWindow.velocityWrites, 1);

    const nextDay = evaluateTeamUsage(nextWindow, {
      collectionId: "leads",
      recordDelta: -1
    }, Date.parse("2026-07-17T00:00:00.000Z"));
    assert.equal(nextDay.dailyWrites, 1);
    assert.equal(nextDay.activeRecords.leads, 0);
  });

  it("warns and briefly limits an unusually fast Team write burst", () => {
    const now = Date.parse("2026-07-16T12:00:00.000Z");
    let state = null;

    for (let count = 1; count <= TEAM_USAGE_POLICY.velocityWarningWrites; count += 1) {
      state = evaluateTeamUsage(state, {
        collectionId: "dutyLocationPoints",
        recordDelta: count % 2 === 0 ? 0 : 1
      }, now + count);
    }
    assert.equal(state.level, "warning");
    assert.equal(state.writesAllowed, true);

    for (
      let count = TEAM_USAGE_POLICY.velocityWarningWrites + 1;
      count <= TEAM_USAGE_POLICY.velocityWriteLimit;
      count += 1
    ) {
      state = evaluateTeamUsage(state, {
        collectionId: "dutySessions",
        recordDelta: 0
      }, now + count);
    }
    assert.equal(state.level, "limited");
    assert.equal(state.writesAllowed, false);
    assert.ok(state.limitedUntilMillis > now);

    const recovered = evaluateTeamUsage(state, {
      collectionId: "dutySessions",
      recordDelta: 0
    }, state.limitedUntilMillis);
    assert.equal(recovered.velocityWrites, 1);
    assert.equal(recovered.writesAllowed, true);
    assert.equal(recovered.level, "normal");
  });

  it("blocks new records at collection capacity without freezing existing work", () => {
    const now = Date.parse("2026-07-16T12:00:00.000Z");
    const leadLimit = TEAM_USAGE_POLICY.recordLimits.leads;
    const previous = {
      activeRecords: { leads: leadLimit - 1 },
      dailyWrites: 40,
      dayKey: "2026-07-16",
      lastPublishedAtMillis: now,
      publishedLevel: "normal",
      velocityWrites: 4,
      windowKey: String(Math.floor(now / TEAM_USAGE_POLICY.velocityWindowMs))
    };
    const decision = evaluateTeamUsage(previous, {
      collectionId: "leads",
      recordDelta: 1
    }, now + 1);

    assert.deepEqual(decision.blockedCollections, ["leads"]);
    assert.equal(decision.writesAllowed, true);
    assert.equal(decision.level, "warning");
    assert.equal(decision.shouldPublish, true);

    const recovered = evaluateTeamUsage(decision, {
      collectionId: "leads",
      recordDelta: -1
    }, now + 2);

    assert.deepEqual(recovered.blockedCollections, []);
    assert.equal(recovered.level, "warning");
    assert.equal(recovered.shouldPublish, true);
  });
});
