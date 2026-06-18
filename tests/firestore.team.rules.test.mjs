import { after, afterEach, before, describe, it } from "node:test";
import fs from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment
} from "@firebase/rules-unit-testing";
import {
  collection,
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
  it("allows the owner create-team batch used by the app", async () => {
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

    await assertSucceeds(batch.commit());
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

    await assertFails(getDoc(doc(repOneDb, "teams/team-1/dutySessions/seeded-session-rep-2")));
    await assertSucceeds(getDoc(doc(repTwoDb, "teams/team-1/dutySessions/seeded-session-rep-2")));
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
    await assertSucceeds(getDocs(collection(ownerDb, "teams/team-1/ownerNotifications")));
    await assertFails(getDocs(collection(repOneDb, "teams/team-1/ownerNotifications")));
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

  it("blocks unauthenticated team access", async () => {
    const db = testEnv.unauthenticatedContext().firestore();

    await assertFails(getDoc(doc(db, "teams/team-1")));
    await assertFails(setDoc(doc(db, "teams/team-1"), teamData("owner-1", Timestamp.now())));
  });
});

async function seedOwnerTeam() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const now = Timestamp.now();
    await setDoc(doc(db, "teams/team-1"), teamData("owner-1", now));
    await setDoc(doc(db, "teams/team-1/members/owner-1"), ownerMemberData("owner-1", now));
  });
}

async function seedTeamWithTwoRepsAndWork() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const now = Timestamp.now();

    await setDoc(doc(db, "teams/team-1"), teamData("owner-1", now));
    await setDoc(doc(db, "teams/team-1/members/owner-1"), ownerMemberData("owner-1", now));
    await setDoc(doc(db, "teams/team-1/members/rep-1"), repMemberData("rep-1", now));
    await setDoc(doc(db, "teams/team-1/members/rep-2"), repMemberData("rep-2", now));

    await setDoc(doc(db, "teams/team-1/leads/lead-rep-1"), leadData("rep-1", now));
    await setDoc(doc(db, "teams/team-1/leads/lead-rep-2"), leadData("rep-2", now));
    await setDoc(doc(db, "teams/team-1/bookings/booking-rep-1"), bookingData("rep-1", now));
    await setDoc(doc(db, "teams/team-1/bookings/booking-rep-2"), bookingData("rep-2", now));
    await setDoc(doc(db, "teams/team-1/dutySessions/seeded-session-rep-2"), dutySessionData("rep-2", now));
  });
}

function teamData(ownerUserId, now) {
  return {
    name: "Test Team",
    ownerUserId,
    createdAt: now,
    updatedAt: now,
    planStatus: "active",
    memberLimit: 3
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
    createdByUserId: "owner-1",
    createdAt: now,
    expiresAt: Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
    status: "pending"
  };
}

function teamProfileData(teamId, role, now) {
  return {
    teamId,
    role,
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
