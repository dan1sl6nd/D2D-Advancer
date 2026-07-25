import { after, afterEach, before, describe, it } from "node:test";
import fs from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch
} from "firebase/firestore";

const projectId = "d2d-advancer-rules-test";
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync("firestore.rules", "utf8")
    }
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

describe("D2D team Firestore rules", () => {
  it("blocks client-created Team plans because the backend owns entitlement state", async () => {
    const db = testEnv.authenticatedContext("owner-1", { email: "owner@example.com" }).firestore();
    const batch = writeBatch(db);
    const now = Timestamp.now();

    batch.set(doc(db, "teams/team-1"), teamData("owner-1", now));
    batch.set(doc(db, "teams/team-1/members/owner-1"), ownerMemberData("owner-1", now));
    batch.set(doc(db, "users/owner-1/teamProfile/current"), teamProfileData("team-1", "owner", now));
    batch.set(doc(db, "teams/team-1/activityLog/team-created"), activityLogData({
      actorUserId: "owner-1",
      kind: "team_created",
      subjectId: "team-1",
      subjectTitle: "Test Team",
      targetUserId: "owner-1",
      now
    }));

    await assertFails(batch.commit());
  });

  it("blocks orphan team documents without the owner member batch", async () => {
    const db = testEnv.authenticatedContext("owner-1", { email: "owner@example.com" }).firestore();
    const now = Timestamp.now();

    await assertFails(setDoc(doc(db, "teams/orphan-team"), teamData("owner-1", now)));
    await assertFails(setDoc(doc(db, "teams/bad-limit-team"), {
      ...teamData("owner-1", now),
      memberLimit: 10
    }));
  });

  it("blocks owner edits to protected team plan fields outside close-team", async () => {
    await seedOwnerTeam();

    const ownerDb = testEnv.authenticatedContext("owner-1", { email: "owner@example.com" }).firestore();
    const now = Timestamp.now();

    await assertFails(updateDoc(doc(ownerDb, "teams/team-1"), {
      memberLimit: 10,
      updatedAt: now
    }));
    await assertFails(updateDoc(doc(ownerDb, "teams/team-1"), {
      ownerUserId: "rep-1",
      updatedAt: now
    }));
    await assertFails(updateDoc(doc(ownerDb, "teams/team-1"), {
      planStatus: "paused",
      updatedAt: now
    }));
  });

  it("uses verified expiration timestamps for active, grace, and paused access", async () => {
    const now = Timestamp.now();
    const ownerDb = testEnv.authenticatedContext("owner-1", { email: "owner@example.com" }).firestore();

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "teams/team-1"), verifiedTeamData("owner-1", now, {
        planExpiresAt: Timestamp.fromMillis(Date.now() + 60_000),
        graceEndsAt: Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000)
      }));
      await setDoc(doc(db, "teams/team-1/members/owner-1"), ownerMemberData("owner-1", now));
    });

    await assertSucceeds(getDoc(doc(ownerDb, "teams/team-1")));
    await assertSucceeds(setDoc(doc(ownerDb, "teams/team-1/leads/active-lead"), leadData("owner-1", now)));

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await updateDoc(doc(db, "teams/team-1"), {
        planExpiresAt: Timestamp.fromMillis(Date.now() - 60_000),
        graceEndsAt: Timestamp.fromMillis(Date.now() + 60_000)
      });
    });

    await assertSucceeds(getDoc(doc(ownerDb, "teams/team-1")));
    await assertFails(setDoc(doc(ownerDb, "teams/team-1/leads/grace-lead"), leadData("owner-1", now)));

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await updateDoc(doc(db, "teams/team-1"), {
        graceEndsAt: Timestamp.fromMillis(Date.now() - 60_000)
      });
    });

    await assertFails(getDoc(doc(ownerDb, "teams/team-1")));
  });

  it("keeps owner member management limited to work type and removal", async () => {
    await seedTeamWithTwoRepsAndWork();

    const ownerDb = testEnv.authenticatedContext("owner-1", { email: "owner@example.com" }).firestore();
    const now = Timestamp.now();

    await assertSucceeds(updateDoc(doc(ownerDb, "teams/team-1/members/rep-1"), {
      workType: "technician",
      updatedAt: now
    }));
    await assertSucceeds(updateDoc(doc(ownerDb, "teams/team-1/members/rep-2"), {
      status: "removed",
      removedAt: now,
      updatedAt: now
    }));
    await assertFails(updateDoc(doc(ownerDb, "teams/team-1/members/rep-1"), {
      role: "owner",
      updatedAt: now
    }));
    await assertFails(updateDoc(doc(ownerDb, "teams/team-1/members/owner-1"), {
      status: "removed",
      removedAt: now,
      updatedAt: now
    }));
  });

  it("allows owner invite creation and a rep single-use join batch", async () => {
    await seedOwnerTeam();

    const ownerDb = testEnv.authenticatedContext("owner-1", { email: "owner@example.com" }).firestore();
    const inviteBatch = writeBatch(ownerDb);
    const now = Timestamp.now();

    inviteBatch.set(doc(ownerDb, "teamInvites/INVITE01"), inviteData(now));
    inviteBatch.set(
      doc(ownerDb, "teams/team-1/members/pending-rep-INVITE01"),
      pendingMemberData(now)
    );
    inviteBatch.set(doc(ownerDb, "teams/team-1/activityLog/invite-created"), activityLogData({
      actorUserId: "owner-1",
      kind: "invite_created",
      subjectId: "INVITE01",
      subjectTitle: "invite INVITE01",
      targetUserId: "pending-rep-INVITE01",
      now
    }));
    await assertSucceeds(inviteBatch.commit());

    const repDb = testEnv.authenticatedContext("rep-1", { email: "rep@example.com" }).firestore();
    await assertSucceeds(getDoc(doc(repDb, "teamInvites/INVITE01")));
    await assertFails(getDocs(collection(repDb, "teamInvites")));

    const joinBatch = writeBatch(repDb);
    joinBatch.delete(doc(repDb, "teams/team-1/members/pending-rep-INVITE01"));
    joinBatch.set(doc(repDb, "teams/team-1/members/rep-1"), repMemberData("rep-1", now));
    joinBatch.update(doc(repDb, "teamInvites/INVITE01"), {
      status: "accepted",
      acceptedByUserId: "rep-1",
      acceptedAt: now
    });
    joinBatch.set(doc(repDb, "users/rep-1/teamProfile/current"), teamProfileData("team-1", "member", now));
    joinBatch.set(doc(repDb, "teams/team-1/activityLog/invite-accepted"), activityLogData({
      actorUserId: "rep-1",
      kind: "invite_accepted",
      subjectId: "INVITE01",
      subjectTitle: "invite accepted",
      targetUserId: "rep-1",
      now
    }));

    await assertSucceeds(joinBatch.commit());
  });

  it("blocks workers from accepting invites outside the join batch", async () => {
    await seedOwnerTeam();
    const now = Timestamp.now();

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "teamInvites/INVITE02"), inviteData(now));
      await setDoc(doc(db, "teamInvites/INVITE03"), inviteData(now));
      await setDoc(doc(db, "teams/team-1/members/pending-rep-INVITE02"), {
        ...pendingMemberData(now),
        userId: "pending-rep-INVITE02",
        acceptedInviteId: "INVITE02"
      });
      await setDoc(doc(db, "teamInvites/EXPIRED1"), {
        ...inviteData(now),
        expiresAt: Timestamp.fromMillis(Date.now() - 60_000)
      });
    });

    const repDb = testEnv.authenticatedContext("rep-1", { email: "rep@example.com" }).firestore();

    await assertFails(updateDoc(doc(repDb, "teamInvites/INVITE02"), {
      status: "accepted",
      acceptedByUserId: "rep-1",
      acceptedAt: now
    }));
    await assertFails(updateDoc(doc(repDb, "teamInvites/INVITE02"), {
      status: "accepted",
      acceptedByUserId: "rep-1",
      acceptedAt: now,
      createdByUserId: "rep-1"
    }));
    await assertFails(setDoc(doc(repDb, "teams/team-1/members/rep-1"), {
      ...repMemberData("rep-1", now),
      acceptedInviteId: "INVITE02"
    }));
    await assertFails(deleteDoc(doc(repDb, "teams/team-1/members/pending-rep-INVITE02")));

    const tamperedJoinBatch = writeBatch(repDb);
    tamperedJoinBatch.set(doc(repDb, "teams/team-1/members/rep-1"), {
      ...repMemberData("rep-1", now),
      acceptedInviteId: "INVITE03"
    });
    tamperedJoinBatch.update(doc(repDb, "teamInvites/INVITE03"), {
      status: "accepted",
      acceptedByUserId: "rep-1",
      acceptedAt: now,
      createdByUserId: "rep-1"
    });
    tamperedJoinBatch.set(doc(repDb, "users/rep-1/teamProfile/current"), teamProfileData("team-1", "member", now));

    await assertFails(tamperedJoinBatch.commit());

    const expiredJoinBatch = writeBatch(repDb);
    expiredJoinBatch.set(doc(repDb, "teams/team-1/members/rep-1"), {
      ...repMemberData("rep-1", now),
      acceptedInviteId: "EXPIRED1"
    });
    expiredJoinBatch.update(doc(repDb, "teamInvites/EXPIRED1"), {
      status: "accepted",
      acceptedByUserId: "rep-1",
      acceptedAt: now
    });
    expiredJoinBatch.set(doc(repDb, "users/rep-1/teamProfile/current"), teamProfileData("team-1", "member", now));

    await assertFails(expiredJoinBatch.commit());
  });

  it("keeps reps limited to their assigned leads and bookings", async () => {
    await seedTeamWithTwoRepsAndWork();

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const repOneDb = testEnv.authenticatedContext("rep-1").firestore();
    const repTwoDb = testEnv.authenticatedContext("rep-2").firestore();

    await assertSucceeds(getDocs(collection(ownerDb, "teams/team-1/leads")));
    await assertSucceeds(getDocs(collection(ownerDb, "teams/team-1/bookings")));

    await assertSucceeds(getDoc(doc(repOneDb, "teams/team-1/leads/lead-rep-1")));
    await assertSucceeds(getDoc(doc(repOneDb, "teams/team-1/bookings/booking-rep-1")));
    await assertFails(getDoc(doc(repOneDb, "teams/team-1/leads/lead-rep-2")));
    await assertFails(getDoc(doc(repOneDb, "teams/team-1/bookings/booking-rep-2")));

    await assertSucceeds(
      getDocs(query(collection(repTwoDb, "teams/team-1/leads"), where("assignedToUserId", "==", "rep-2")))
    );
    await assertFails(getDocs(collection(repTwoDb, "teams/team-1/leads")));
  });

  it("keeps rep-created lead and booking payloads scoped to the team path", async () => {
    await seedTeamWithTwoRepsAndWork();

    const repDb = testEnv.authenticatedContext("rep-1").firestore();
    const now = Timestamp.now();
    const validLead = leadData("rep-1", now);
    const validBooking = bookingData("rep-1", now);

    await assertSucceeds(setDoc(doc(repDb, "teams/team-1/leads/new-lead-rep-1"), validLead));
    await assertSucceeds(setDoc(doc(repDb, "teams/team-1/bookings/new-booking-rep-1"), validBooking));

    await assertFails(setDoc(doc(repDb, "teams/team-1/leads/wrong-team-lead"), {
      ...validLead,
      teamId: "other-team"
    }));
    await assertFails(setDoc(doc(repDb, "teams/team-1/leads/wrong-assignee-lead"), {
      ...validLead,
      assignedToUserId: "rep-2"
    }));
    await assertFails(updateDoc(doc(repDb, "teams/team-1/leads/lead-rep-1"), {
      teamId: "other-team",
      updatedByUserId: "rep-1",
      updatedAt: now
    }));
    await assertFails(updateDoc(doc(repDb, "teams/team-1/leads/lead-rep-1"), {
      createdByUserId: "owner-1",
      updatedByUserId: "rep-1",
      updatedAt: now
    }));

    await assertFails(setDoc(doc(repDb, "teams/team-1/bookings/wrong-team-booking"), {
      ...validBooking,
      teamId: "other-team"
    }));
    await assertFails(updateDoc(doc(repDb, "teams/team-1/bookings/booking-rep-1"), {
      assignedToUserId: "rep-2",
      updatedByUserId: "rep-1",
      updatedAt: now
    }));
  });

  it("allows assigned reps to clear optional lead and booking fields with null merge payloads", async () => {
    await seedTeamWithTwoRepsAndWork();

    const repDb = testEnv.authenticatedContext("rep-1").firestore();
    const now = Timestamp.now();

    await assertSucceeds(updateDoc(doc(repDb, "teams/team-1/leads/lead-rep-1"), {
      phone: null,
      email: null,
      serviceCategory: null,
      highPriorityReason: null,
      updatedByUserId: "rep-1",
      updatedAt: now
    }));
    await assertSucceeds(updateDoc(doc(repDb, "teams/team-1/bookings/booking-rep-1"), {
      customerName: null,
      customerPhone: null,
      customerEmail: null,
      serviceCategory: null,
      quotedPrice: null,
      latitude: null,
      longitude: null,
      arrivalWindowMinutes: null,
      updatedByUserId: "rep-1",
      updatedAt: now
    }));
  });

  it("keeps owner lead and booking writes scoped to the team path", async () => {
    await seedTeamWithTwoRepsAndWork();

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const now = Timestamp.now();

    await assertSucceeds(setDoc(doc(ownerDb, "teams/team-1/leads/owner-good-lead"), leadData("rep-1", now)));
    await assertSucceeds(setDoc(doc(ownerDb, "teams/team-1/bookings/owner-good-booking"), bookingData("rep-1", now)));
    await assertFails(setDoc(doc(ownerDb, "teams/team-1/leads/owner-wrong-team-lead"), {
      ...leadData("rep-1", now),
      teamId: "other-team"
    }));
    await assertFails(setDoc(doc(ownerDb, "teams/team-1/bookings/owner-wrong-team-booking"), {
      ...bookingData("rep-1", now),
      teamId: "other-team"
    }));
    await assertFails(updateDoc(doc(ownerDb, "teams/team-1/leads/lead-rep-1"), {
      teamId: "other-team",
      updatedByUserId: "owner-1",
      updatedAt: now
    }));
  });

  it("lets reps manage only their own active-hour sessions", async () => {
    await seedTeamWithTwoRepsAndWork();

    const repOneDb = testEnv.authenticatedContext("rep-1").firestore();
    const repTwoDb = testEnv.authenticatedContext("rep-2").firestore();
    const now = Timestamp.now();

    await assertSucceeds(
      setDoc(doc(repOneDb, "teams/team-1/dutySessions/session-rep-1"), {
        teamId: "team-1",
        repUserId: "rep-1",
        startedAt: now,
        status: "active",
        createdAt: now,
        distanceMeters: 0
      })
    );

    await assertFails(
      setDoc(doc(repOneDb, "teams/team-1/dutySessions/session-rep-2"), {
        teamId: "team-1",
        repUserId: "rep-2",
        startedAt: now,
        status: "active",
        createdAt: now,
        distanceMeters: 0
      })
    );
    await assertFails(
      setDoc(doc(repOneDb, "teams/team-1/dutySessions/session-wrong-team"), {
        teamId: "other-team",
        repUserId: "rep-1",
        startedAt: now,
        status: "active",
        createdAt: now,
        distanceMeters: 0
      })
    );
    await assertFails(
      setDoc(doc(repOneDb, "teams/team-1/dutyLocationPoints/point-wrong-team"), {
        ...dutyLocationPointData("rep-1", "session-rep-1", now),
        teamId: "other-team"
      })
    );

    await assertFails(getDoc(doc(repOneDb, "teams/team-1/dutySessions/seeded-session-rep-2")));
    await assertSucceeds(getDoc(doc(repTwoDb, "teams/team-1/dutySessions/seeded-session-rep-2")));
    await assertSucceeds(getDoc(doc(repOneDb, "teams/team-1/members/owner-1")));
    await assertFails(getDoc(doc(repOneDb, "teams/team-1/members/rep-2")));
    await assertSucceeds(
      getDocs(query(collection(repOneDb, "teams/team-1/dutySessions"), where("repUserId", "==", "owner-1")))
    );
    await assertSucceeds(
      getDocs(query(collection(repOneDb, "teams/team-1/dutyLocationPoints"), where("repUserId", "==", "owner-1")))
    );
    await assertFails(getDoc(doc(repOneDb, "teams/team-1/dutyLocationPoints/seeded-point-rep-2")));
  });

  it("lets reps create owner alerts but keeps the alert inbox owner-only", async () => {
    await seedTeamWithTwoRepsAndWork();

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const repOneDb = testEnv.authenticatedContext("rep-1").firestore();
    const now = Timestamp.now();

    await assertSucceeds(
      setDoc(
        doc(repOneDb, "teams/team-1/ownerNotifications/alert-rep-1"),
        ownerNotificationData("rep-1", now)
      )
    );
    await assertFails(
      setDoc(
        doc(repOneDb, "teams/team-1/ownerNotifications/alert-rep-2"),
        ownerNotificationData("rep-2", now)
      )
    );
    await assertFails(
      setDoc(
        doc(repOneDb, "teams/team-1/ownerNotifications/alert-wrong-team"),
        {
          ...ownerNotificationData("rep-1", now),
          teamId: "other-team"
        }
      )
    );
    await assertSucceeds(getDocs(collection(ownerDb, "teams/team-1/ownerNotifications")));
    await assertFails(getDocs(collection(repOneDb, "teams/team-1/ownerNotifications")));
  });

  it("lets owners mark owner alerts read and write the audit log", async () => {
    await seedTeamWithTwoRepsAndWork();

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const repOneDb = testEnv.authenticatedContext("rep-1").firestore();
    const now = Timestamp.now();

    await assertSucceeds(
      setDoc(
        doc(repOneDb, "teams/team-1/ownerNotifications/alert-rep-1"),
        ownerNotificationData("rep-1", now)
      )
    );

    const readBatch = writeBatch(ownerDb);
    readBatch.update(doc(ownerDb, "teams/team-1/ownerNotifications/alert-rep-1"), {
      readAt: now
    });
    readBatch.set(doc(ownerDb, "teams/team-1/activityLog/owner-read-alert"), activityLogData({
      actorUserId: "owner-1",
      kind: "owner_alert_read",
      subjectId: "alert-rep-1",
      subjectTitle: "Rep marked a lead interested",
      targetUserId: "rep-1",
      now
    }));

    await assertSucceeds(readBatch.commit());
    await assertSucceeds(getDoc(doc(ownerDb, "teams/team-1/ownerNotifications/alert-rep-1")));
    await assertFails(
      updateDoc(doc(repOneDb, "teams/team-1/ownerNotifications/alert-rep-1"), {
        readAt: now
      })
    );
  });

  it("keeps activity log visible to owner and scoped reps only", async () => {
    await seedTeamWithTwoRepsAndWork();

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const repOneDb = testEnv.authenticatedContext("rep-1").firestore();
    const repTwoDb = testEnv.authenticatedContext("rep-2").firestore();
    const now = Timestamp.now();

    await assertSucceeds(
      setDoc(doc(repOneDb, "teams/team-1/activityLog/rep-1-entry"), activityLogData({
        actorUserId: "rep-1",
        kind: "rep_status_reply",
        subjectId: "lead-rep-1",
        subjectTitle: "Done",
        targetUserId: "rep-1",
        now
      }))
    );

    await assertSucceeds(getDocs(collection(ownerDb, "teams/team-1/activityLog")));
    await assertSucceeds(
      getDocs(query(collection(repOneDb, "teams/team-1/activityLog"), where("targetUserId", "==", "rep-1")))
    );
    await assertFails(getDoc(doc(repTwoDb, "teams/team-1/activityLog/rep-1-entry")));
  });

  it("blocks workers from editing their own team privileges", async () => {
    await seedTeamWithTwoRepsAndWork();

    const repDb = testEnv.authenticatedContext("rep-1").firestore();
    const now = Timestamp.now();
    const memberRef = doc(repDb, "teams/team-1/members/rep-1");

    await assertFails(updateDoc(memberRef, {
      role: "owner",
      updatedAt: now
    }));
    await assertFails(updateDoc(memberRef, {
      workType: "technician",
      updatedAt: now
    }));
    await assertFails(updateDoc(memberRef, {
      role: "owner",
      status: "removed",
      removedAt: now,
      updatedAt: now
    }));
  });

  it("allows a worker to leave their own team and lose team access", async () => {
    await seedTeamWithTwoRepsAndWork();

    const repDb = testEnv.authenticatedContext("rep-1").firestore();
    const now = Timestamp.now();
    const batch = writeBatch(repDb);

    batch.update(doc(repDb, "teams/team-1/members/rep-1"), {
      status: "removed",
      removedAt: now,
      updatedAt: now
    });
    batch.delete(doc(repDb, "users/rep-1/teamProfile/current"));
    batch.set(doc(repDb, "teams/team-1/activityLog/rep-left"), activityLogData({
      actorUserId: "rep-1",
      kind: "member_left",
      subjectId: "rep-1",
      subjectTitle: "Test Team",
      targetUserId: "rep-1",
      now
    }));

    await assertSucceeds(batch.commit());
    await assertFails(getDoc(doc(repDb, "teams/team-1")));
  });

  it("allows the owner to close the team workspace and remove members", async () => {
    await seedTeamWithTwoRepsAndWork();

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const now = Timestamp.now();
    const batch = writeBatch(ownerDb);

    batch.update(doc(ownerDb, "teams/team-1"), {
      planStatus: "paused",
      updatedAt: now
    });
    for (const userId of ["owner-1", "rep-1", "rep-2"]) {
      batch.update(doc(ownerDb, `teams/team-1/members/${userId}`), {
        status: "removed",
        removedAt: now,
        updatedAt: now
      });
    }
    for (const sessionId of ["seeded-session-owner", "seeded-session-rep-2"]) {
      batch.update(doc(ownerDb, `teams/team-1/dutySessions/${sessionId}`), {
        status: "ended",
        endedAt: now,
        lastLocationAt: now,
        deleteAfter: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000)
      });
    }
    batch.delete(doc(ownerDb, "users/owner-1/teamProfile/current"));
    batch.set(doc(ownerDb, "teams/team-1/activityLog/team-closed"), activityLogData({
      actorUserId: "owner-1",
      kind: "team_closed",
      subjectId: "team-1",
      subjectTitle: "Test Team",
      targetUserId: "owner-1",
      now
    }));

    await assertSucceeds(batch.commit());
  });

  it("allows a verified owner to close a team with a pending invite using the narrow app payload", async () => {
    const createdAt = Timestamp.fromMillis(Date.now() - 60_000);
    const closeAt = Timestamp.now();
    const planExpiresAt = Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000);
    const graceEndsAt = Timestamp.fromMillis(Date.now() + 37 * 24 * 60 * 60 * 1000);

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "teams/team-1"), verifiedTeamData("owner-1", createdAt, {
        planExpiresAt,
        graceEndsAt
      }));
      await setDoc(doc(db, "teams/team-1/members/owner-1"), ownerMemberData("owner-1", createdAt));
      await setDoc(
        doc(db, "teams/team-1/members/pending-rep-INVITE01"),
        pendingMemberData(createdAt)
      );
      await setDoc(doc(db, "teamInvites/INVITE01"), inviteData(createdAt));
      await setDoc(
        doc(db, "users/owner-1/teamProfile/current"),
        teamProfileData("team-1", "owner", createdAt)
      );
    });

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const batch = writeBatch(ownerDb);
    batch.set(doc(ownerDb, "teams/team-1"), {
      updatedAt: closeAt,
      planStatus: "paused"
    }, { merge: true });
    batch.delete(doc(ownerDb, "users/owner-1/teamProfile/current"));
    batch.set(doc(ownerDb, "teams/team-1/members/owner-1"), {
      ...ownerMemberData("owner-1", createdAt),
      status: "removed",
      workType: "owner",
      removedAt: closeAt,
      updatedAt: closeAt
    }, { merge: true });
    batch.set(doc(ownerDb, "teams/team-1/members/pending-rep-INVITE01"), {
      ...pendingMemberData(createdAt),
      status: "removed",
      workType: "sales_rep",
      removedAt: closeAt,
      updatedAt: closeAt
    }, { merge: true });
    batch.delete(doc(ownerDb, "teamInvites/INVITE01"));
    batch.set(doc(ownerDb, "teams/team-1/activityLog/team-closed-with-invite"), activityLogData({
      actorUserId: "owner-1",
      kind: "team_closed",
      subjectId: "team-1",
      subjectTitle: "Test Team",
      targetUserId: "owner-1",
      now: closeAt
    }));

    await assertSucceeds(batch.commit());
  });

  it("keeps grace teams read-only and blocks normal team edits", async () => {
    await seedTeamWithTwoRepsAndWork("grace");

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const repDb = testEnv.authenticatedContext("rep-1").firestore();
    const now = Timestamp.now();

    await assertSucceeds(getDoc(doc(ownerDb, "teams/team-1")));
    await assertSucceeds(getDoc(doc(repDb, "teams/team-1/leads/lead-rep-1")));

    await assertFails(setDoc(doc(ownerDb, "teamInvites/GRACE01"), inviteData(now)));
    await assertFails(updateDoc(doc(ownerDb, "teams/team-1/members/rep-1"), {
      workType: "technician",
      updatedAt: now
    }));
    await assertFails(setDoc(doc(repDb, "teams/team-1/leads/grace-rep-lead"), leadData("rep-1", now)));
    await assertFails(setDoc(doc(ownerDb, "teams/team-1/bookings/grace-owner-booking"), bookingData("rep-1", now)));
    await assertFails(setDoc(doc(repDb, "teams/team-1/ownerNotifications/grace-alert"), ownerNotificationData("rep-1", now)));
    await assertFails(setDoc(doc(repDb, "teams/team-1/dutySessions/grace-session"), dutySessionData("rep-1", now)));
    await assertFails(setDoc(doc(repDb, "teams/team-1/dutyLocationPoints/grace-point"), dutyLocationPointData("rep-1", "seeded-session-rep-2", now)));
  });

  it("blocks paused team reads but still lets workers leave", async () => {
    await seedTeamWithTwoRepsAndWork("paused");

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const repDb = testEnv.authenticatedContext("rep-1").firestore();
    const now = Timestamp.now();

    await assertFails(getDoc(doc(ownerDb, "teams/team-1")));
    await assertFails(getDoc(doc(repDb, "teams/team-1/leads/lead-rep-1")));
    await assertFails(setDoc(doc(ownerDb, "teams/team-1/leads/paused-owner-lead"), leadData("rep-1", now)));

    const leaveBatch = writeBatch(repDb);
    leaveBatch.update(doc(repDb, "teams/team-1/members/rep-1"), {
      status: "removed",
      removedAt: now,
      updatedAt: now
    });
    leaveBatch.delete(doc(repDb, "users/rep-1/teamProfile/current"));
    leaveBatch.set(doc(repDb, "teams/team-1/activityLog/paused-rep-left"), activityLogData({
      actorUserId: "rep-1",
      kind: "member_left",
      subjectId: "rep-1",
      subjectTitle: "Test Team",
      targetUserId: "rep-1",
      now
    }));

    await assertSucceeds(leaveBatch.commit());
  });

  it("lets owners close a grace team without reopening edits", async () => {
    await seedTeamWithTwoRepsAndWork("grace");

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const now = Timestamp.now();
    const batch = writeBatch(ownerDb);

    batch.update(doc(ownerDb, "teams/team-1"), {
      planStatus: "paused",
      updatedAt: now
    });
    for (const userId of ["owner-1", "rep-1", "rep-2"]) {
      batch.update(doc(ownerDb, `teams/team-1/members/${userId}`), {
        status: "removed",
        removedAt: now,
        updatedAt: now
      });
    }
    for (const sessionId of ["seeded-session-owner", "seeded-session-rep-2"]) {
      batch.update(doc(ownerDb, `teams/team-1/dutySessions/${sessionId}`), {
        status: "ended",
        endedAt: now,
        lastLocationAt: now,
        deleteAfter: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000)
      });
    }
    batch.delete(doc(ownerDb, "users/owner-1/teamProfile/current"));
    batch.set(doc(ownerDb, "teams/team-1/activityLog/grace-team-closed"), activityLogData({
      actorUserId: "owner-1",
      kind: "team_closed",
      subjectId: "team-1",
      subjectTitle: "Test Team",
      targetUserId: "owner-1",
      now
    }));

    await assertSucceeds(batch.commit());
  });

  it("pauses normal Team writes globally while preserving reads and safe exit actions", async () => {
    await seedTeamWithTwoRepsAndWork();
    const now = Timestamp.now();

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "serviceControls/teamOperations"), {
        teamWritesEnabled: false,
        message: "Team edits are temporarily paused while usage is checked.",
        reason: "budget_threshold",
        updatedAt: now
      });
      await setDoc(
        doc(db, "users/rep-1/teamProfile/current"),
        teamProfileData("team-1", "member", now)
      );
    });

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const repOneDb = testEnv.authenticatedContext("rep-1").firestore();
    const repTwoDb = testEnv.authenticatedContext("rep-2").firestore();

    await assertSucceeds(getDoc(doc(ownerDb, "serviceControls/teamOperations")));
    await assertSucceeds(getDoc(doc(ownerDb, "teams/team-1")));
    await assertSucceeds(getDoc(doc(ownerDb, "teams/team-1/leads/lead-rep-1")));
    await assertFails(setDoc(doc(ownerDb, "teams/team-1/leads/blocked-lead"), leadData("owner-1", now)));
    await assertFails(updateDoc(doc(ownerDb, "serviceControls/teamOperations"), {
      teamWritesEnabled: true,
      updatedAt: now
    }));

    const dutyEndBatch = writeBatch(repTwoDb);
    dutyEndBatch.update(doc(repTwoDb, "teams/team-1/dutySessions/seeded-session-rep-2"), {
      status: "ended",
      endedAt: now,
      deleteAfter: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000)
    });
    dutyEndBatch.set(doc(repTwoDb, "teams/team-1/activityLog/paused-duty-ended"), activityLogData({
      actorUserId: "rep-2",
      kind: "duty_ended",
      subjectId: "seeded-session-rep-2",
      subjectTitle: "duty",
      targetUserId: "rep-2",
      now
    }));
    await assertSucceeds(dutyEndBatch.commit());

    const leaveBatch = writeBatch(repOneDb);
    leaveBatch.update(doc(repOneDb, "teams/team-1/members/rep-1"), {
      status: "removed",
      removedAt: now,
      updatedAt: now
    });
    leaveBatch.delete(doc(repOneDb, "users/rep-1/teamProfile/current"));
    leaveBatch.set(doc(repOneDb, "teams/team-1/activityLog/paused-member-left"), activityLogData({
      actorUserId: "rep-1",
      kind: "member_left",
      subjectId: "rep-1",
      subjectTitle: "Test Team",
      targetUserId: "rep-1",
      now
    }));
    await assertSucceeds(leaveBatch.commit());
  });

  it("pauses ordinary writes for a live team cooldown while preserving reads and safe exits", async () => {
    await seedTeamWithTwoRepsAndWork();
    const now = Timestamp.now();

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "teamUsageControls/team-1"), teamUsageControlData({
        now,
        level: "limited",
        writesAllowed: false,
        limitedUntil: Timestamp.fromMillis(Date.now() + 60_000)
      }));
    });

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    const repDb = testEnv.authenticatedContext("rep-2").firestore();

    await assertSucceeds(getDoc(doc(ownerDb, "teamUsageControls/team-1")));
    await assertSucceeds(getDoc(doc(ownerDb, "teams/team-1/leads/lead-rep-1")));
    await assertFails(setDoc(
      doc(ownerDb, "teams/team-1/leads/cooldown-lead"),
      leadData("owner-1", now)
    ));
    await assertFails(updateDoc(doc(ownerDb, "teamUsageControls/team-1"), {
      writesAllowed: true
    }));

    const dutyEndBatch = writeBatch(repDb);
    dutyEndBatch.update(doc(repDb, "teams/team-1/dutySessions/seeded-session-rep-2"), {
      status: "ended",
      endedAt: now,
      deleteAfter: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000)
    });
    dutyEndBatch.set(doc(repDb, "teams/team-1/activityLog/usage-duty-ended"), activityLogData({
      actorUserId: "rep-2",
      kind: "duty_ended",
      subjectId: "seeded-session-rep-2",
      subjectTitle: "duty",
      targetUserId: "rep-2",
      now
    }));
    await assertSucceeds(dutyEndBatch.commit());
  });

  it("blocks only capped collection creates while allowing edits and other collections", async () => {
    await seedTeamWithTwoRepsAndWork();
    const now = Timestamp.now();

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "teamUsageControls/team-1"), teamUsageControlData({
        now,
        level: "warning",
        writesAllowed: true,
        blockedCollections: ["leads"]
      }));
    });

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();

    await assertFails(setDoc(
      doc(ownerDb, "teams/team-1/leads/capacity-lead"),
      leadData("owner-1", now)
    ));
    await assertSucceeds(updateDoc(doc(ownerDb, "teams/team-1/leads/lead-rep-1"), {
      name: "Updated Lead",
      updatedAt: now,
      updatedByUserId: "owner-1"
    }));
    await assertSucceeds(setDoc(
      doc(ownerDb, "teams/team-1/bookings/capacity-booking"),
      bookingData("owner-1", now)
    ));
  });

  it("allows writes after a team usage cooldown expires", async () => {
    await seedOwnerTeam();
    const now = Timestamp.now();

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "teamUsageControls/team-1"), teamUsageControlData({
        now,
        level: "limited",
        writesAllowed: false,
        limitedUntil: Timestamp.fromMillis(Date.now() - 60_000)
      }));
    });

    const ownerDb = testEnv.authenticatedContext("owner-1").firestore();
    await assertSucceeds(setDoc(
      doc(ownerDb, "teams/team-1/leads/recovered-lead"),
      leadData("owner-1", now)
    ));
  });

  it("blocks unauthenticated team access", async () => {
    const db = testEnv.unauthenticatedContext().firestore();

    await assertFails(getDoc(doc(db, "teams/team-1")));
    await assertFails(setDoc(doc(db, "teams/team-1"), teamData("owner-1", Timestamp.now())));
  });
});

async function seedOwnerTeam(planStatus = "active") {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const now = Timestamp.now();
    await setDoc(doc(db, "teams/team-1"), teamData("owner-1", now, planStatus));
    await setDoc(doc(db, "teams/team-1/members/owner-1"), ownerMemberData("owner-1", now));
  });
}

async function seedTeamWithTwoRepsAndWork(planStatus = "active") {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const now = Timestamp.now();

    await setDoc(doc(db, "teams/team-1"), teamData("owner-1", now, planStatus));
    await setDoc(doc(db, "teams/team-1/members/owner-1"), ownerMemberData("owner-1", now));
    await setDoc(doc(db, "teams/team-1/members/rep-1"), repMemberData("rep-1", now));
    await setDoc(doc(db, "teams/team-1/members/rep-2"), repMemberData("rep-2", now));

    await setDoc(doc(db, "teams/team-1/leads/lead-rep-1"), leadData("rep-1", now));
    await setDoc(doc(db, "teams/team-1/leads/lead-rep-2"), leadData("rep-2", now));
    await setDoc(doc(db, "teams/team-1/bookings/booking-rep-1"), bookingData("rep-1", now));
    await setDoc(doc(db, "teams/team-1/bookings/booking-rep-2"), bookingData("rep-2", now));
    await setDoc(doc(db, "teams/team-1/dutySessions/seeded-session-owner"), dutySessionData("owner-1", now));
    await setDoc(doc(db, "teams/team-1/dutySessions/seeded-session-rep-2"), dutySessionData("rep-2", now));
    await setDoc(doc(db, "teams/team-1/dutyLocationPoints/seeded-point-owner"), dutyLocationPointData("owner-1", "seeded-session-owner", now));
    await setDoc(doc(db, "teams/team-1/dutyLocationPoints/seeded-point-rep-2"), dutyLocationPointData("rep-2", "seeded-session-rep-2", now));
  });
}

function teamData(ownerUserId, now, planStatus = "active") {
  return {
    name: "Test Team",
    ownerUserId,
    createdAt: now,
    updatedAt: now,
    planStatus,
    memberLimit: 3
  };
}

function verifiedTeamData(ownerUserId, now, { planExpiresAt, graceEndsAt }) {
  return {
    ...teamData(ownerUserId, now),
    billingOriginalTransactionId: "1000000001",
    billingProductId: "com.d2dadvancer.team3.yearly",
    billingSource: "app_store",
    graceEndsAt,
    planExpiresAt,
    schemaVersion: 2
  };
}

function ownerMemberData(userId, now) {
  return {
    teamId: "team-1",
    userId,
    displayName: "Owner Test",
    email: "owner@example.com",
    role: "owner",
    status: "active",
    joinedAt: now,
    updatedAt: now
  };
}

function repMemberData(userId, now) {
  return {
    teamId: "team-1",
    userId,
    displayName: "Rep Test",
    email: `${userId}@example.com`,
    role: "member",
    status: "active",
    acceptedInviteId: "INVITE01",
    joinedAt: now,
    updatedAt: now
  };
}

function pendingMemberData(now) {
  return {
    teamId: "team-1",
    userId: "pending-rep-INVITE01",
    displayName: "Pending Rep",
    role: "member",
    status: "active",
    acceptedInviteId: "INVITE01",
    joinedAt: now,
    updatedAt: now
  };
}

function inviteData(now) {
  return {
    teamId: "team-1",
    teamName: "North Crew",
    ownerDisplayName: "Owner One",
    createdByUserId: "owner-1",
    createdAt: now,
    expiresAt: Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
    status: "pending",
    planStatus: "active",
    workType: "sales_rep"
  };
}

function teamProfileData(teamId, role, now) {
  return {
    teamId,
    role,
    updatedAt: now
  };
}

function teamUsageControlData({
  now,
  level = "normal",
  writesAllowed = true,
  limitedUntil = null,
  blockedCollections = []
}) {
  return {
    teamId: "team-1",
    level,
    writesAllowed,
    limitedUntil,
    blockedCollections,
    dailyWrites: 0,
    dailyWriteLimit: 5_000,
    velocityWrites: 0,
    velocityWriteLimit: 300,
    velocityWindowMinutes: 15,
    activeRecords: {},
    recordLimits: {},
    message: level === "normal" ? "Team usage is normal." : "Team usage is temporarily limited.",
    updatedAt: now
  };
}

function leadData(assignedToUserId, now) {
  return {
    teamId: "team-1",
    name: "Lead",
    address: "123 Test St",
    latitude: 43.6,
    longitude: -79.7,
    status: "interested",
    assignedToUserId,
    createdByUserId: assignedToUserId,
    updatedByUserId: assignedToUserId,
    createdAt: now,
    updatedAt: now
  };
}

function bookingData(assignedToUserId, now) {
  return {
    teamId: "team-1",
    leadId: `lead-${assignedToUserId}`,
    assignedToUserId,
    title: "Booking",
    startDate: now,
    endDate: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
    location: "123 Test St",
    status: "scheduled",
    createdByUserId: assignedToUserId,
    updatedByUserId: assignedToUserId,
    createdAt: now,
    updatedAt: now
  };
}

function dutySessionData(repUserId, now) {
  return {
    teamId: "team-1",
    repUserId,
    startedAt: now,
    status: "active",
    createdAt: now,
    distanceMeters: 0
  };
}

function dutyLocationPointData(repUserId, sessionId, now) {
  return {
    teamId: "team-1",
    sessionId,
    repUserId,
    latitude: 43.6,
    longitude: -79.7,
    horizontalAccuracy: 12,
    recordedAt: now,
    deleteAfter: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000)
  };
}

function ownerNotificationData(repUserId, now) {
  return {
    teamId: "team-1",
    leadId: `lead-${repUserId}`,
    assignedToUserId: repUserId,
    createdByUserId: repUserId,
    eventType: "lead_interested",
    title: "Rep marked a lead interested",
    message: "Lead at 123 Test St",
    createdAt: now
  };
}

function activityLogData({ actorUserId, kind, subjectId, subjectTitle, targetUserId, now }) {
  return {
    teamId: "team-1",
    actorUserId,
    actorDisplayName: actorUserId === "owner-1" ? "Owner Test" : "Rep Test",
    kind,
    subjectId,
    subjectTitle,
    targetUserId,
    summary: `${actorUserId} ${kind} ${subjectTitle}`,
    createdAt: now
  };
}
