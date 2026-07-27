# Team Firebase Cost Controls

This design limits the blast radius of a billing or abuse incident. It does not pretend that a Google Cloud budget is a hard spending cap. Budget notifications can be delayed, and usage already accepted by Google can still be billed.

## Controls in the repository

- Solo accounts keep personal leads and appointments in iCloud. Firebase is limited to account metadata and is not used for always-on personal lead listeners.
- Each Team workspace is metered independently. One noisy customer cannot directly consume another Team's allowance.
- A Team receives a warning at 3,000 document writes per UTC day or 180 writes in 15 minutes. It is temporarily limited at 5,000 writes per day or 300 writes in 15 minutes.
- The iOS client independently stops one device at 150 document writes per 15 minutes, before the shared Team ceiling is reached.
- New records stop at explicit workspace capacities: 3,000 leads, 1,500 bookings, 100,000 retained GPS points, 5,000 activity entries, and 1,000 owner notifications. Existing records can still be edited or removed.
- Team listeners are bounded and reused across Map, Leads, Work, More, and Team. The workspace neither performs a complete initial fetch before listening nor restarts healthy listeners on every tab change.
- GPS points require both a minimum time interval and meaningful movement, with a two-minute heartbeat. Duty-session metadata is written at most every five minutes.
- Cloud Functions default to `minInstances: 0`, `maxInstances: 3`, `256MiB`, one Gen 1 CPU, and a 30-second timeout.
- Cloud Functions run as `d2d-team-runtime@d2d-advancer.iam.gserviceaccount.com`, which has Firestore data access but no Cloud Build role.
- The default Compute service account is used by Cloud Build and is not used as the Functions runtime identity.
- `createTeamWorkspace` allows five attempts per authenticated user per hour.
- `syncTeamEntitlement` allows 30 attempts per authenticated user per hour.
- Apple server notifications reject malformed or oversized payloads before signature verification.
- The billing budget topic `d2d-firebase-budget-alerts` pauses Team writes at 80% of the configured budget.
- Firestore rules enforce the pause for current and old app versions.
- Existing Team data remains readable while writes are paused.
- Going off duty, leaving a Team, and closing a Team remain available during a pause.
- Clients can read `/serviceControls/teamOperations`, but only trusted backend/Admin tooling can edit it.
- App Check is included in the iOS client. Callable enforcement stays off until the staged rollout below is complete.

Metering event documents use `expiresAt`; GPS sessions, GPS points, activity entries, and owner notifications use `deleteAfter`. Firestore TTL must be enabled for each collection group after deployment so old data is deleted automatically.

## Unit economics guardrail

The local StoreKit configuration prices the included owner plus two-worker Team plan at USD 39.99 monthly or USD 319.99 yearly. Even under a conservative 30% App Store commission assumption, that leaves about USD 27.99 per monthly subscriber or USD 18.67 per month from an annual subscriber before backend cost.

The 5,000-write daily Team ceiling is 150,000 client writes in a 30-day month. The idempotent meter adds roughly two backend writes and two transaction reads per source write, plus one Function invocation. Ignoring the shared Firebase free allowance, current Iowa list pricing puts those Firestore operations around USD 0.52 per maximally active Team per month before storage, egress, logs, and other services. The operating target is therefore:

- keep normal Team backend cost below USD 1 per month;
- investigate any Team consistently above the warning threshold;
- keep at least 90% contribution margin after App Store commission and backend cost;
- review actual billing export data monthly instead of treating this estimate as a guarantee.

Cloud Billing budgets remain delayed alarms, not hard caps. The per-device limiter, per-Team rules, collection capacities, instance ceilings, and global 80% budget pause are the actual layered safeguards.

## Required deployment order

Do not deploy only the hardened Firestore rules while the production Team Functions are absent. Team creation is backend-owned and will fail.

1. Upgrade `d2d-advancer` to Blaze and set a Cloud Billing budget with several thresholds, including 50%, 80%, 90%, and 100%. Start with a deliberately low amount such as CAD 25 until real usage is measured.
2. Create or select the Pub/Sub topic `d2d-firebase-budget-alerts`.
3. Connect the Cloud Billing budget's programmatic notifications to `projects/d2d-advancer/topics/d2d-firebase-budget-alerts` with schema version `1.0`. Let the Cloud Billing Budget API install its managed publisher binding; do not hard-code a legacy Google system principal.

   This project inherits `iam.allowedPolicyMemberDomains`, which can block Cloud Billing from adding its managed publisher. If that happens, temporarily override only this constraint on `d2d-advancer`, connect the topic, inspect the resulting topic IAM policy, and immediately delete the project override so the inherited restriction is restored. Never leave the project exempt from domain-restricted sharing.

   Keep the default email recipients enabled, then verify the budget shows both the topic and all four thresholds. Do not publish a synthetic message at or above 80% in production because it will intentionally pause Team writes.
4. Create `functions/.env.d2d-advancer` locally with `D2D_ENFORCE_TEAM_APP_CHECK=false`.
5. Confirm the dedicated runtime service account exists and has `roles/datastore.user` and `roles/eventarc.eventReceiver`. The Eventarc role is required for the Firestore-backed `meterTeamUsage` trigger; the direct Pub/Sub budget trigger does not need it. Confirm the default Compute service account has `roles/cloudbuild.builds.builder` for function builds. Do not grant the runtime account Cloud Build permissions.
6. Deploy Functions first:

   ```bash
   firebase deploy --project d2d-advancer --only functions
   ```

7. This project uses domain-restricted sharing, which blocks Firebase CLI's normal `allUsers` invoker binding. Disable the Cloud Run Invoker IAM check only for the intended public entry points after each Functions deploy:

   ```bash
   gcloud run services update appstoreservernotifications --project=d2d-advancer --region=us-central1 --no-invoker-iam-check
   gcloud run services update createteamworkspace --project=d2d-advancer --region=us-central1 --no-invoker-iam-check
   gcloud run services update syncteamentitlement --project=d2d-advancer --region=us-central1 --no-invoker-iam-check
   ```

   Keep the legacy `pauseteamwritesonbudget` HTTPS compatibility service protected by its Invoker IAM check.

   The Eventarc-backed budget listener and Firestore usage meter stay private. Their triggers use the dedicated runtime identity, so grant that identity `run.invoker` only on those two services:

   ```bash
   gcloud run services add-iam-policy-binding pauseteamwritesonbudgetalert \
     --project=d2d-advancer \
     --region=us-central1 \
     --member="serviceAccount:d2d-team-runtime@d2d-advancer.iam.gserviceaccount.com" \
     --role="roles/run.invoker"
   gcloud run services add-iam-policy-binding meterteamusage \
     --project=d2d-advancer \
     --region=us-central1 \
     --member="serviceAccount:d2d-team-runtime@d2d-advancer.iam.gserviceaccount.com" \
     --role="roles/run.invoker"
   ```

   Direct Pub/Sub events do not require `roles/eventarc.eventReceiver`; the Firestore trigger does. Do not grant project-wide `run.invoker` when these service-level bindings are sufficient. Verify the meter with a controlled write and confirm Cloud Run logs show `204`, not `403`.

8. Confirm these Functions exist and have successful logs:
   - `createTeamWorkspace`
   - `syncTeamEntitlement`
   - `meterTeamUsage`
   - `appStoreServerNotifications`
   - `pauseTeamWritesOnBudgetAlert`

   `pauseTeamWritesOnBudget` remains as a private HTTPS compatibility resource because Google Cloud cannot change an existing function's trigger type in place. It can be deleted after the Pub/Sub listener has been verified in production.
9. Deploy Firestore rules and the bounded-query composite indexes:

   ```bash
   firebase deploy --project d2d-advancer --only firestore:rules,firestore:indexes
   ```

10. Enable TTL for all ephemeral collections and confirm each state becomes `ACTIVE`:

    ```bash
    gcloud firestore fields ttls update expiresAt \
      --project=d2d-advancer \
      --collection-group=serverRateLimits \
      --enable-ttl
    gcloud firestore fields ttls update expiresAt --project=d2d-advancer --collection-group=teamUsageEvents --enable-ttl
    gcloud firestore fields ttls update deleteAfter --project=d2d-advancer --collection-group=dutySessions --enable-ttl
    gcloud firestore fields ttls update deleteAfter --project=d2d-advancer --collection-group=dutyLocationPoints --enable-ttl
    gcloud firestore fields ttls update deleteAfter --project=d2d-advancer --collection-group=activityLog --enable-ttl
    gcloud firestore fields ttls update deleteAfter --project=d2d-advancer --collection-group=ownerNotifications --enable-ttl
    gcloud firestore fields ttls list --project=d2d-advancer
    ```

    TTL deletion is asynchronous and is normally completed within roughly 24 hours after a document expires. TTL deletes are billed document deletes.

11. Ship an iOS build with App Check configured. The Simulator uses the debug provider; physical devices use App Attest with the production App Attest entitlement.
12. Register the iOS app with App Attest in Firebase App Check, register only required Simulator debug tokens, and monitor App Check metrics until supported builds consistently send valid tokens. Firebase does not accept App Attest sandbox tokens, so physical development builds must also use the production entitlement.
13. Change `D2D_ENFORCE_TEAM_APP_CHECK=true`, redeploy the callable Functions, and test one owner and one worker on supported physical builds.

Enabling App Check enforcement before the client rollout is verified will break Team calls for installed older builds. That is not security; it is a self-inflicted outage.

## Production verification

The 2026-07-16 rollout verified the following live state:

- the CAD 25 monthly budget targets only `d2d-advancer`, publishes to `d2d-firebase-budget-alerts`, and has 50%, 80%, 90%, and 100% current-spend thresholds;
- all six Team-related Functions are active under the dedicated runtime identity;
- the private `meterTeamUsage` service accepts Eventarc delivery through a service-level `roles/run.invoker` binding;
- all six TTL policies are `ACTIVE`;
- an isolated create/delete smoke test produced two successful metered writes and was removed completely;
- an isolated lead-cap test published `blockedCollections: ["leads"]` at 3,000 records and cleared it after returning to 2,999 records;
- the three pre-existing Team documents were backfilled with their actual record counts so capacity enforcement does not start from zero.

Cloud Billing budgets are still delayed alarms rather than hard caps. These checks prove the deployed safeguards are connected; they do not remove the need to review billing and usage logs during the first month.

## Manual emergency pause

In Firestore, create or update this trusted document:

`serviceControls/teamOperations`

Use these fields:

```text
teamWritesEnabled: false
message: "Team edits are temporarily paused while usage is checked. Existing team data remains available."
reason: "manual_review"
source: "firebase_console"
pausedAt: <server timestamp>
updatedAt: <server timestamp>
```

To resume after reviewing usage and logs, set `teamWritesEnabled` to `true` and update `updatedAt`. The budget Function intentionally never auto-resumes Team writes.

## What this does not guarantee

- `maxInstances` limits concurrency; it does not cap total invocations over a month.
- The per-Team ceiling bounds application writes; it does not stop every possible Google Cloud charge or malicious traffic outside the supported app paths.
- Firestore, Auth, Pub/Sub, networking, and retained logs can still generate charges.
- A budget notification is an alarm, not a real-time circuit breaker.
- Detaching billing automatically can disable unrelated services and still cannot reverse charges already incurred, so this design pauses the costly Team write path instead.
- The first month still requires daily billing review and low alert thresholds. Raise the budget only from measured usage, not guesses.

Official setup references:

- [Firebase App Check for Apple platforms](https://firebase.google.com/docs/app-check/ios/app-attest-provider)
- [Firebase App Check debug provider](https://firebase.google.com/docs/app-check/ios/debug-provider)
- [Cloud Functions instance limits](https://firebase.google.com/docs/functions/manage-functions)
- [Cloud Firestore pricing](https://firebase.google.com/docs/firestore/pricing)
- [Cloud Firestore TTL policies](https://firebase.google.com/docs/firestore/ttl)
- [Automate responses to billing notifications](https://firebase.google.com/docs/projects/billing/advanced-billing-alerts-logic)
- [Cloud Billing programmatic notifications](https://cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications)
