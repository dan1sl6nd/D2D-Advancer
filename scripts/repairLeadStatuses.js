#!/usr/bin/env node
/*
 One-time Firestore status normalizer for D2D Advancer

 - Scans users/{uid}/leads and normalizes legacy/custom status strings
 - Maps common synonyms (e.g., "sold", "closed", "won") to canonical app values
 - Dry-run by default; pass --apply to write changes
 - Optionally target a single user via --user=<uid>

 Usage:
   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
   node scripts/repairLeadStatuses.js --project=<projectId> [--user=<uid>] [--apply]

 Notes:
 - Requires: npm i firebase-admin
 - Backups: writes a JSON report with proposed changes (and applied ones when --apply)
*/

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

// ---------- CLI args ----------
const argv = process.argv.slice(2);
const hasFlag = (f) => argv.some((a) => a === f);
const getArg = (name) => {
  const prefix = `--${name}=`;
  const hit = argv.find((a) => a.startsWith(prefix));
  return hit ? hit.replace(prefix, '') : undefined;
};

const APPLY = hasFlag('--apply');
const PROJECT = getArg('project') || process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID;
const ONLY_USER = getArg('user');

if (!PROJECT) {
  console.error('Missing project id. Pass --project=<id> or set FIREBASE_PROJECT_ID.');
  process.exit(1);
}

// ---------- Firebase init ----------
try {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT,
  });
} catch (e) {
  console.error('Failed to initialize Firebase Admin. Ensure GOOGLE_APPLICATION_CREDENTIALS is set.');
  console.error(e);
  process.exit(1);
}

const db = admin.firestore();

// ---------- Normalization logic ----------
function normalizeStatus(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const s = raw.trim().toLowerCase().replace(/[\s-]+/g, '_');

  // Canonical values used by the app
  const canonical = new Set([
    'not_contacted',
    'not_home',
    'interested',
    'converted', // Sold
    'not_interested',
  ]);

  if (canonical.has(s)) return s;

  // Synonyms → canonical
  const map = new Map([
    // Sold/Signed/Closed/Won
    ['sold', 'converted'],
    ['closed', 'converted'],
    ['close', 'converted'],
    ['closed_won', 'converted'],
    ['closedwon', 'converted'],
    ['won', 'converted'],
    ['contract_signed', 'converted'],
    ['signed', 'converted'],
    ['purchased', 'converted'],
    ['sale', 'converted'],

    // Not Interested
    ['no_interest', 'not_interested'],
    ['not_interested', 'not_interested'], // already handled above, but safe
    ['declined', 'not_interested'],
    ['rejected', 'not_interested'],
    ['lost', 'not_interested'],
    ['do_not_contact', 'not_interested'],
    ['dnc', 'not_interested'],

    // Not Home
    ['no_answer', 'not_home'],
    ['not_home', 'not_home'],
    ['noone_home', 'not_home'],
    ['left_card', 'not_home'],

    // Interested / Prospect
    ['prospect', 'interested'],
    ['engaged', 'interested'],
    ['hot', 'interested'],
    ['warm', 'interested'],
    ['qualified', 'interested'],

    // New / Not Contacted
    ['new', 'not_contacted'],
    ['cold', 'not_contacted'],
    ['uncontacted', 'not_contacted'],
    ['fresh', 'not_contacted'],
  ]);

  return map.get(s) || null; // null → unknown
}

async function run() {
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const reportPath = path.join(process.cwd(), `status_repair_report_${ts}.json`);
  const report = { project: PROJECT, dryRun: !APPLY, usersScanned: 0, leadsScanned: 0, changes: [], unknowns: [] };

  const userQuery = ONLY_USER
    ? [db.collection('users').doc(ONLY_USER)]
    : (await db.collection('users').get()).docs.map((d) => d.ref);

  console.log(`Scanning ${userQuery.length} user(s)${APPLY ? ' (apply mode)' : ' (dry-run)'}...`);

  const writer = db.bulkWriter ? db.bulkWriter() : null;
  let applyCount = 0;

  for (const userRef of userQuery) {
    report.usersScanned++;
    const leadsSnap = await userRef.collection('leads').get();
    if (leadsSnap.empty) continue;

    for (const leadDoc of leadsSnap.docs) {
      report.leadsScanned++;
      const data = leadDoc.data() || {};
      const current = (data.status || '').toString();
      const normalized = normalizeStatus(current);

      if (!current) continue; // no status to repair

      if (!normalized) {
        // Unknown value; collect for manual review
        report.unknowns.push({ user: userRef.id, lead: leadDoc.id, current });
        continue;
      }

      if (normalized !== current) {
        report.changes.push({ user: userRef.id, lead: leadDoc.id, from: current, to: normalized });
        if (APPLY) {
          if (writer) {
            writer.update(leadDoc.ref, { status: normalized });
          } else {
            await leadDoc.ref.update({ status: normalized });
          }
          applyCount++;
        }
      }
    }
  }

  if (writer) await writer.close();

  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(`\nReport written to: ${reportPath}`);
  console.log(`Users scanned: ${report.usersScanned}`);
  console.log(`Leads scanned: ${report.leadsScanned}`);
  console.log(`Changes detected: ${report.changes.length}`);
  if (APPLY) console.log(`Changes applied: ${applyCount}`);
  if (report.unknowns.length) console.log(`Unknown statuses: ${report.unknowns.length} (inspect report file)\n`);
}

run().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});

