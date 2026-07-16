# Team Firebase Cost Controls

This design limits the blast radius of a billing or abuse incident. It does not pretend that a Google Cloud budget is a hard spending cap. Budget notifications can be delayed, and usage already accepted by Google can still be billed.

## Controls in the repository

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

Rate-limit documents include an `expiresAt` field. Firestore TTL must be enabled for `serverRateLimits.expiresAt` after deployment so old counters are deleted automatically.

## Required deployment order

Do not deploy only the hardened Firestore rules while the production Team Functions are absent. Team creation is backend-owned and will fail.

1. Upgrade `d2d-advancer` to Blaze and set a Cloud Billing budget with several thresholds, including 50%, 80%, 90%, and 100%. Start with a deliberately low amount such as CAD 25 until real usage is measured.
2. Create or select the Pub/Sub topic `d2d-firebase-budget-alerts`.
3. Connect the Cloud Billing budget's programmatic notifications to `projects/d2d-advancer/topics/d2d-firebase-budget-alerts` with schema version `1.0`. Let the Cloud Billing Budget API install its managed publisher binding; do not hard-code a legacy Google system principal.

   This project inherits `iam.allowedPolicyMemberDomains`, which can block Cloud Billing from adding its managed publisher. If that happens, temporarily override only this constraint on `d2d-advancer`, connect the topic, inspect the resulting topic IAM policy, and immediately delete the project override so the inherited restriction is restored. Never leave the project exempt from domain-restricted sharing.

   Keep the default email recipients enabled, then verify the budget shows both the topic and all four thresholds. Do not publish a synthetic message at or above 80% in production because it will intentionally pause Team writes.
4. Create `functions/.env.d2d-advancer` locally with `D2D_ENFORCE_TEAM_APP_CHECK=false`.
5. Confirm the dedicated runtime service account exists and has `roles/datastore.user`. Confirm the default Compute service account has `roles/cloudbuild.builds.builder` for function builds. Do not grant the runtime account Cloud Build permissions.
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

   The budget listener stays private. Its Pub/Sub Eventarc trigger uses the dedicated runtime identity, so grant that identity `run.invoker` only on the listener service:

   ```bash
   gcloud run services add-iam-policy-binding pauseteamwritesonbudgetalert \
     --project=d2d-advancer \
     --region=us-central1 \
     --member="serviceAccount:d2d-team-runtime@d2d-advancer.iam.gserviceaccount.com" \
     --role="roles/run.invoker"
   ```

   Direct Pub/Sub events do not require `roles/eventarc.eventReceiver`. Do not grant project-wide `run.invoker` when this service-level binding is sufficient.

8. Confirm these Functions exist and have successful logs:
   - `createTeamWorkspace`
   - `syncTeamEntitlement`
   - `appStoreServerNotifications`
   - `pauseTeamWritesOnBudgetAlert`

   `pauseTeamWritesOnBudget` remains as a private HTTPS compatibility resource because Google Cloud cannot change an existing function's trigger type in place. It can be deleted after the Pub/Sub listener has been verified in production.
9. Deploy Firestore rules:

   ```bash
   firebase deploy --project d2d-advancer --only firestore:rules
   ```

10. Enable TTL for expired server rate-limit documents and confirm the state becomes `ACTIVE`:

    ```bash
    gcloud firestore fields ttls update expiresAt \
      --project=d2d-advancer \
      --collection-group=serverRateLimits \
      --enable-ttl
    gcloud firestore fields ttls list \
      --project=d2d-advancer \
      --collection-group=serverRateLimits
    ```

11. Ship an iOS build with App Check configured. The Simulator uses the debug provider; physical devices use DeviceCheck.
12. Register the iOS app in Firebase App Check, register only required Simulator debug tokens, and monitor App Check metrics until supported builds consistently send valid tokens.
13. Change `D2D_ENFORCE_TEAM_APP_CHECK=true`, redeploy the callable Functions, and test one owner and one worker on supported physical builds.

Enabling App Check enforcement before the client rollout is verified will break Team calls for installed older builds. That is not security; it is a self-inflicted outage.

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
- Firestore, Auth, Pub/Sub, networking, and retained logs can still generate charges.
- A budget notification is an alarm, not a real-time circuit breaker.
- Detaching billing automatically can disable unrelated services and still cannot reverse charges already incurred, so this design pauses the costly Team write path instead.
- The first month still requires daily billing review and low alert thresholds. Raise the budget only from measured usage, not guesses.

Official setup references:

- [Firebase App Check for Apple platforms](https://firebase.google.com/docs/app-check/ios/app-attest-provider)
- [Firebase App Check debug provider](https://firebase.google.com/docs/app-check/ios/debug-provider)
- [Cloud Functions instance limits](https://firebase.google.com/docs/functions/manage-functions)
- [Automate responses to billing notifications](https://firebase.google.com/docs/projects/billing/advanced-billing-alerts-logic)
- [Cloud Billing programmatic notifications](https://cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications)
