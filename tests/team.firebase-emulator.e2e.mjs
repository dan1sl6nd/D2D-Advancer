import assert from "node:assert/strict";
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

const projectId = "d2d-advancer";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;

test("created owner and rep Firebase accounts can create and join a team", async () => {
  assert.ok(authHost, "FIREBASE_AUTH_EMULATOR_HOST must be set by firebase emulators:exec");
  assert.ok(firestoreHost, "FIRESTORE_EMULATOR_HOST must be set by firebase emulators:exec");

  const runId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const teamId = `team-${runId}`;
  const inviteCode = `E2E${runId.replace(/[^A-Z0-9]/gi, "").slice(-6).toUpperCase()}`;

  const owner = await createTestAccount("owner", runId, "Owner E2E");
  const rep = await createTestAccount("rep", runId, "Rep E2E");

  try {
    await createOwnerTeam(owner.db, {
      teamId,
      ownerUserId: owner.uid,
      ownerEmail: owner.email
    });

    await createInvite(owner.db, {
      teamId,
      ownerUserId: owner.uid,
      inviteCode
    });

    await joinTeam(rep.db, {
      teamId,
      repUserId: rep.uid,
      repEmail: rep.email,
      inviteCode
    });

    await assertTeamVisibility({
      ownerDb: owner.db,
      repDb: rep.db,
      teamId,
      ownerUserId: owner.uid,
      repUserId: rep.uid
    });
  } finally {
    await Promise.allSettled([deleteApp(owner.app), deleteApp(rep.app)]);
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

  const email = `d2d-${role}-${runId}@example.com`;
  const credential = await createUserWithEmailAndPassword(auth, email, "TestPass123!");
  await updateProfile(credential.user, { displayName });

  return {
    app,
    db,
    email,
    uid: credential.user.uid
  };
}

async function createOwnerTeam(db, { teamId, ownerUserId, ownerEmail }) {
  const now = Timestamp.now();
  const batch = writeBatch(db);

  batch.set(doc(db, "teams", teamId), {
    name: "E2E Team",
    ownerUserId,
    createdAt: now,
    updatedAt: now,
    planStatus: "active",
    memberLimit: 3
  });
  batch.set(doc(db, "teams", teamId, "members", ownerUserId), {
    teamId,
    userId: ownerUserId,
    displayName: "Owner E2E",
    email: ownerEmail,
    role: "owner",
    status: "active",
    joinedAt: now,
    updatedAt: now
  });
  batch.set(doc(db, "users", ownerUserId, "teamProfile", "current"), {
    teamId,
    role: "owner",
    updatedAt: now
  });

  await batch.commit();
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

async function joinTeam(db, { teamId, repUserId, repEmail, inviteCode }) {
  const now = Timestamp.now();
  const batch = writeBatch(db);

  batch.delete(doc(db, "teams", teamId, "members", `pending-rep-${inviteCode}`));
  batch.set(doc(db, "teams", teamId, "members", repUserId), {
    teamId,
    userId: repUserId,
    displayName: "Rep E2E",
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

async function assertTeamVisibility({ ownerDb, repDb, teamId, ownerUserId, repUserId }) {
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
  assert.equal(ownerMembers.size, 2, "owner sees active owner and rep member records after invite join");

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
}
