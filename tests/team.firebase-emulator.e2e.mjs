import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { initializeApp, deleteApp } from "firebase/app";
import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
  updateProfile
} from "firebase/auth";
import {
  collection,
  connectFirestoreEmulator,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  query,
  setDoc,
  Timestamp,
  where,
  writeBatch
} from "firebase/firestore";
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable
} from "firebase/functions";

const projectId = "d2d-advancer";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
// Firebase CLI does not export this variable in every release. The fallback
// matches the fixed Functions emulator port in firebase.json and is never used
// unless Auth and Firestore emulator variables prove this is an emulator run.
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1:5001";

test("created owner and rep Firebase accounts can create and join a team", async () => {
  assert.ok(authHost, "FIREBASE_AUTH_EMULATOR_HOST must be set by firebase emulators:exec");
  assert.ok(firestoreHost, "FIRESTORE_EMULATOR_HOST must be set by firebase emulators:exec");

  const runId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const inviteCode = randomBytes(4).toString("hex").toUpperCase();

  const owner = await createTestAccount("owner", runId, "Owner E2E");
  const rep = await createTestAccount("rep", runId, "Rep E2E");
  const technician = await createTestAccount("tech", runId, "Technician E2E");

  try {
    const teamId = await createOwnerTeam(owner.functions);

    await createInvite(owner.db, {
      teamId,
      ownerUserId: owner.uid,
      inviteCode
    });

    const preview = await httpsCallable(rep.functions, "getTeamInvitePreview")({ inviteCode });
    assert.equal(preview.data.teamId, teamId);
    assert.equal(preview.data.teamName, "E2E Team");
    assert.equal(preview.data.planStatus, "active");
    assert.equal(preview.data.workType, "sales_rep");

    await joinTeam(rep.db, {
      teamId,
      repUserId: rep.uid,
      repEmail: rep.email,
      inviteCode
    });

    const technicianInviteCode = randomBytes(4).toString("hex").toUpperCase();
    await createInvite(owner.db, {
      teamId,
      ownerUserId: owner.uid,
      inviteCode: technicianInviteCode
    });

    await joinTeam(technician.db, {
      teamId,
      repUserId: technician.uid,
      repEmail: technician.email,
      inviteCode: technicianInviteCode,
      displayName: "Technician E2E"
    });

    await setWorkerType(owner.db, {
      teamId,
      workerUserId: technician.uid,
      workType: "technician"
    });

    await assertTeamVisibility({
      ownerDb: owner.db,
      repDb: rep.db,
      technicianDb: technician.db,
      teamId,
      ownerUserId: owner.uid,
      repUserId: rep.uid,
      technicianUserId: technician.uid
    });

    await closeOwnerTeam(owner.db, {
      teamId,
      ownerUserId: owner.uid
    });
    const replacementTeamId = await createOwnerTeam(owner.functions);
    assert.notEqual(
      replacementTeamId,
      teamId,
      "closing a workspace allows the same verified owner entitlement to create a replacement"
    );

    const replacementProfile = await getDoc(
      doc(owner.db, "users", owner.uid, "teamProfile", "current")
    );
    assert.equal(
      replacementProfile.data()?.teamId,
      replacementTeamId,
      "owner profile points to the replacement workspace"
    );
  } finally {
    await Promise.allSettled([
      deleteApp(owner.app),
      deleteApp(rep.app),
      deleteApp(technician.app)
    ]);
  }
});

async function createTestAccount(role, runId, displayName) {
  const app = initializeApp(
    {
      projectId,
      apiKey: "fake-api-key",
      authDomain: "localhost"
    },
    `d2d-${role}-${runId}`
  );
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${authHost}`, { disableWarnings: true });

  const db = getFirestore(app);
  const [host, port] = firestoreHost.split(":");
  connectFirestoreEmulator(db, host, Number(port));

  const functions = getFunctions(app);
  const [callableHost, callablePort] = functionsHost.split(":");
  connectFunctionsEmulator(functions, callableHost, Number(callablePort));

  const email = `d2d-${role}-${runId}@example.com`;
  const credential = await createUserWithEmailAndPassword(auth, email, "TestPass123!");
  await updateProfile(credential.user, { displayName });

  return {
    app,
    db,
    email,
    functions,
    uid: credential.user.uid
  };
}

async function createOwnerTeam(functions) {
  const result = await httpsCallable(functions, "createTeamWorkspace")({
    displayName: "Owner E2E",
    email: "owner@example.com",
    name: "E2E Team",
    signedTransaction: "D2D_EMULATOR_TEAM_ENTITLEMENT"
  });
  assert.equal(result.data.planStatus, "active");
  assert.equal(result.data.memberLimit, 3);
  assert.ok(result.data.teamId);
  return result.data.teamId;
}

async function closeOwnerTeam(db, { teamId, ownerUserId }) {
  const now = Timestamp.now();
  const members = await getDocs(collection(db, "teams", teamId, "members"));
  const activeDutySessions = await getDocs(
    query(collection(db, "teams", teamId, "dutySessions"), where("status", "==", "active"))
  );
  const batch = writeBatch(db);

  batch.update(doc(db, "teams", teamId), {
    planStatus: "paused",
    updatedAt: now
  });
  batch.delete(doc(db, "users", ownerUserId, "teamProfile", "current"));
  for (const member of members.docs) {
    if (member.data().status !== "active") {
      continue;
    }
    batch.update(member.ref, {
      status: "removed",
      removedAt: now,
      updatedAt: now
    });
  }
  for (const session of activeDutySessions.docs) {
    batch.update(session.ref, {
      status: "ended",
      endedAt: now,
      lastLocationAt: now,
      deleteAfter: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000)
    });
  }
  batch.set(doc(db, "teams", teamId, "activityLog", "team-closed"), {
    teamId,
    actorUserId: ownerUserId,
    kind: "team_closed",
    subjectId: teamId,
    subjectTitle: "E2E Team",
    targetUserId: ownerUserId,
    createdAt: now
  });

  await batch.commit();

  await assert.rejects(
    () => getDoc(doc(db, "teams", teamId)),
    /permission|PERMISSION_DENIED/i,
    "owner loses access to the closed workspace before creating a replacement"
  );
}

async function createInvite(db, { teamId, ownerUserId, inviteCode }) {
  const now = Timestamp.now();
  const batch = writeBatch(db);

  batch.set(doc(db, "teamInvites", inviteCode), {
    teamId,
    createdByUserId: ownerUserId,
    createdAt: now,
    expiresAt: Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
    status: "pending"
  });
  batch.set(doc(db, "teams", teamId, "members", `pending-rep-${inviteCode}`), {
    teamId,
    userId: `pending-rep-${inviteCode}`,
    displayName: "Pending Rep",
    role: "member",
    status: "active",
    acceptedInviteId: inviteCode,
    joinedAt: now,
    updatedAt: now
  });

  await batch.commit();
}

async function joinTeam(db, { teamId, repUserId, repEmail, inviteCode, displayName = "Rep E2E" }) {
  const now = Timestamp.now();
  const batch = writeBatch(db);

  batch.delete(doc(db, "teams", teamId, "members", `pending-rep-${inviteCode}`));
  batch.set(doc(db, "teams", teamId, "members", repUserId), {
    teamId,
    userId: repUserId,
    displayName,
    email: repEmail,
    role: "member",
    status: "active",
    acceptedInviteId: inviteCode,
    joinedAt: now,
    updatedAt: now
  });
  batch.update(doc(db, "teamInvites", inviteCode), {
    status: "accepted",
    acceptedByUserId: repUserId,
    acceptedAt: now
  });
  batch.set(doc(db, "users", repUserId, "teamProfile", "current"), {
    teamId,
    role: "member",
    updatedAt: now
  });

  await batch.commit();
}

async function setWorkerType(db, { teamId, workerUserId, workType }) {
  await writeBatch(db)
    .update(doc(db, "teams", teamId, "members", workerUserId), {
      workType,
      updatedAt: Timestamp.now()
    })
    .commit();
}

async function assertTeamVisibility({
  ownerDb,
  repDb,
  technicianDb,
  teamId,
  ownerUserId,
  repUserId,
  technicianUserId
}) {
  const now = Timestamp.now();

  await setDoc(doc(repDb, "teams", teamId, "leads", "rep-created-lead"), {
    teamId,
    name: "Rep Lead",
    address: "123 Test St",
    latitude: 43.6,
    longitude: -79.7,
    status: "interested",
    assignedToUserId: repUserId,
    createdByUserId: repUserId,
    updatedByUserId: repUserId,
    createdAt: now,
    updatedAt: now
  });
  await setDoc(doc(repDb, "teams", teamId, "ownerNotifications", "rep-created-lead-interested"), {
    teamId,
    leadId: "rep-created-lead",
    assignedToUserId: repUserId,
    createdByUserId: repUserId,
    eventType: "lead_interested",
    title: "Rep marked a lead interested",
    message: "Rep Lead at 123 Test St",
    createdAt: now
  });
  await setDoc(doc(ownerDb, "teams", teamId, "leads", "owner-only-lead"), {
    teamId,
    name: "Owner Lead",
    address: "456 Test Ave",
    latitude: 43.7,
    longitude: -79.6,
    status: "not_contacted",
    assignedToUserId: ownerUserId,
    createdByUserId: ownerUserId,
    updatedByUserId: ownerUserId,
    createdAt: now,
    updatedAt: now
  });

  const ownerMembers = await getDocs(collection(ownerDb, "teams", teamId, "members"));
  assert.equal(ownerMembers.size, 3, "owner sees owner, sales rep, and technician records after invite joins");

  const repProfile = await getDoc(doc(repDb, "users", repUserId, "teamProfile", "current"));
  assert.equal(repProfile.data()?.teamId, teamId, "rep profile points at joined team");

  const repAssignedLeads = await getDocs(
    query(collection(repDb, "teams", teamId, "leads"), where("assignedToUserId", "==", repUserId))
  );
  assert.equal(repAssignedLeads.size, 1, "rep can query only their assigned lead");

  const ownerNotifications = await getDocs(collection(ownerDb, "teams", teamId, "ownerNotifications"));
  assert.equal(ownerNotifications.size, 1, "owner sees the rep-created important-lead notification");
  assert.equal(ownerNotifications.docs[0].data().eventType, "lead_interested");

  await assert.rejects(
    () => getDoc(doc(repDb, "teams", teamId, "leads", "owner-only-lead")),
    /permission|PERMISSION_DENIED/i,
    "rep cannot read a lead assigned to the owner"
  );
  await assert.rejects(
    () => getDocs(collection(repDb, "teams", teamId, "ownerNotifications")),
    /permission|PERMISSION_DENIED/i,
    "rep cannot read owner alert inbox"
  );

  await setDoc(doc(repDb, "teams", teamId, "dutySessions", "rep-session"), {
    teamId,
    repUserId,
    startedAt: now,
    status: "active",
    createdAt: now,
    distanceMeters: 0
  });
  await setDoc(doc(repDb, "teams", teamId, "dutyLocationPoints", "rep-location-point"), {
    teamId,
    repUserId,
    sessionId: "rep-session",
    latitude: 43.6,
    longitude: -79.7,
    horizontalAccuracy: 8,
    recordedAt: now,
    deleteAfter: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000)
  });

  const ownerLocationPoint = await getDoc(doc(ownerDb, "teams", teamId, "dutyLocationPoints", "rep-location-point"));
  assert.equal(ownerLocationPoint.data()?.repUserId, repUserId, "owner can read rep duty location points");

  await assert.rejects(
    () => setDoc(doc(repDb, "teams", teamId, "dutySessions", "owner-session"), {
      teamId,
      repUserId: ownerUserId,
      startedAt: now,
      status: "active",
      createdAt: now,
      distanceMeters: 0
    }),
    /permission|PERMISSION_DENIED/i,
    "rep cannot write another user's duty session"
  );
  await assert.rejects(
    () => setDoc(doc(repDb, "teams", teamId, "dutyLocationPoints", "owner-location-point"), {
      teamId,
      repUserId: ownerUserId,
      sessionId: "owner-session",
      latitude: 43.7,
      longitude: -79.6,
      horizontalAccuracy: 8,
      recordedAt: now,
      deleteAfter: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000)
    }),
    /permission|PERMISSION_DENIED/i,
    "rep cannot write another user's duty location point"
  );

  const jobStart = Timestamp.fromMillis(Date.now() + 2 * 60 * 60 * 1000);
  const jobEnd = Timestamp.fromMillis(Date.now() + 3 * 60 * 60 * 1000);
  const jobPayload = {
    teamId,
    leadId: "rep-created-lead",
    assignedToUserId: technicianUserId,
    title: "Window Cleaning - Rep Lead",
    notes: "Phone: 555-0100\nETA: 30 minute arrival window",
    startDate: jobStart,
    endDate: jobEnd,
    location: "123 Test St",
    status: "scheduled",
    createdByUserId: ownerUserId,
    updatedByUserId: ownerUserId,
    createdAt: now,
    updatedAt: now,
    customerName: "Rep Lead",
    customerPhone: "555-0100",
    customerEmail: "customer@example.com",
    serviceCategory: "Window Cleaning",
    quotedPrice: 350,
    latitude: 43.6,
    longitude: -79.7,
    arrivalWindowMinutes: 30
  };

  await setDoc(doc(ownerDb, "teams", teamId, "bookings", "technician-job"), jobPayload);

  const technicianJob = await getDoc(doc(technicianDb, "teams", teamId, "bookings", "technician-job"));
  assert.equal(technicianJob.data()?.assignedToUserId, technicianUserId, "technician can read their assigned job");
  assert.equal(technicianJob.data()?.arrivalWindowMinutes, 30, "technician job includes approximate arrival window");
  assert.equal(technicianJob.data()?.customerPhone, "555-0100", "technician job includes customer contact details");

  await assert.rejects(
    () => getDoc(doc(technicianDb, "teams", teamId, "leads", "rep-created-lead")),
    /permission|PERMISSION_DENIED/i,
    "technician cannot read an unassigned sales lead directly"
  );

  await setDoc(doc(technicianDb, "teams", teamId, "bookings", "technician-job"), {
    ...jobPayload,
    status: "completed",
    updatedByUserId: technicianUserId,
    updatedAt: Timestamp.now()
  });

  const completedJob = await getDoc(doc(ownerDb, "teams", teamId, "bookings", "technician-job"));
  assert.equal(completedJob.data()?.status, "completed", "owner sees technician job status update");

  const repLeaveBatch = writeBatch(repDb);
  repLeaveBatch.update(doc(repDb, "teams", teamId, "members", repUserId), {
    status: "removed",
    removedAt: Timestamp.now(),
    updatedAt: Timestamp.now()
  });
  repLeaveBatch.delete(doc(repDb, "users", repUserId, "teamProfile", "current"));
  repLeaveBatch.set(doc(repDb, "teams", teamId, "activityLog", "rep-left"), {
    teamId,
    actorUserId: repUserId,
    kind: "member_left",
    subjectId: repUserId,
    subjectTitle: "E2E Team",
    targetUserId: repUserId,
    createdAt: Timestamp.now()
  });
  await repLeaveBatch.commit();

  await assert.rejects(
    () => getDoc(doc(repDb, "teams", teamId)),
    /permission|PERMISSION_DENIED/i,
    "sales rep loses team access after leaving"
  );

  const ownerRemoveTechnicianBatch = writeBatch(ownerDb);
  ownerRemoveTechnicianBatch.update(doc(ownerDb, "teams", teamId, "members", technicianUserId), {
    status: "removed",
    removedAt: Timestamp.now(),
    updatedAt: Timestamp.now()
  });
  ownerRemoveTechnicianBatch.set(doc(ownerDb, "teams", teamId, "activityLog", "technician-removed"), {
    teamId,
    actorUserId: ownerUserId,
    kind: "member_removed",
    subjectId: technicianUserId,
    subjectTitle: "Technician E2E",
    targetUserId: technicianUserId,
    createdAt: Timestamp.now()
  });
  await ownerRemoveTechnicianBatch.commit();

  await assert.rejects(
    () => getDoc(doc(technicianDb, "teams", teamId)),
    /permission|PERMISSION_DENIED/i,
    "technician loses team access after owner removal"
  );
}
