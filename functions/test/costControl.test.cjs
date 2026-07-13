const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const {
  CREATE_TEAM_RATE_LIMIT,
  TEAM_BUDGET_LOCK_RATIO,
  evaluateFixedWindowRateLimit,
  evaluateTeamBudgetAlert
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
});
