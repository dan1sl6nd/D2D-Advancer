# D2D Advancer App Store Release Checklist

Last audited: July 27, 2026

This file separates local engineering proof from App Store Connect and production-service proof. Do not mark an item complete based on simulator evidence alone.

## Product Identity

- App Store app ID: `6751178741`
- Bundle ID: `dan1sland.D2D-Advancer`
- Developer Team ID: `RF247ARQB7`
- Live App Store version: `1.2`
- Release candidate: `1.3 (4)`
- Next unused project build number: `5` or higher
- Minimum iOS version: `18.5`
- Category: Business

Build `4` was uploaded successfully on July 27, 2026. Do not reuse it for another `1.3` upload.

## Current Release Snapshot

- App Store upload UUID: `81916891-bc94-4a0e-ac69-32fbeb925d57`.
- App Store Connect upload transfer: complete, with no errors or warnings.
- App Store Connect build processing: still pending; Apple has not yet exposed build `1.3 (4)` as a selectable processed build.
- App version state: `READY_FOR_REVIEW`.
- Review draft: five items, still consisting of iOS `1.3 (3)` and the four new Solo/Team subscriptions until build `1.3 (4)` can be attached.
- TestFlight: build `1.3 (3)` is assigned to automatic-distribution group `Internal QA`, but the group has zero testers. The account holder is the only App Store Connect user and Apple disables that row in the tester picker.
- Simulator Team proof: Firebase-emulator owner, sales-rep, and technician end-to-end UI test passed on iPhone 17 Pro simulator, iOS 26.4.1.
- Simulator regression proof: all nine UI scenarios that were killed at zero duration in the overloaded 287-test run passed in focused reruns; the seeded Apple Contacts import also passed against a clean temporary simulator Contacts store.
- Physical proof: build `1.3 (4)` was installed over the existing app on `dan1sland iPhone 17`, iOS 26.5.2. Production App Attest reached the strict `syncTeamEntitlement` callable's input validation without a Team write. A copied app-data container confirmed that all 3,049 leads remained in the Core Data store.
- Submission is intentionally not started. TestFlight purchase and restore are not yet verified.

## Toolchain Requirement

Apple requires iOS submissions to be built with Xcode 26 or later and the iOS 26 SDK as of April 28, 2026. The release audit used Xcode 26.6. Recheck Apple's upcoming requirements page immediately before upload.

## Subscription Products

Subscription group: `Premium Access`

| Product | Product ID | Duration | Intended US price | Availability |
| --- | --- | --- | --- | --- |
| Solo Monthly | `com.d2dadvancer.solo.monthly` | 1 month | USD 14.99 | New paywall |
| Solo Yearly | `com.d2dadvancer.solo.yearly` | 1 year | USD 119.99 | New paywall |
| Team Monthly | `com.d2dadvancer.team3.monthly` | 1 month | USD 39.99 | New paywall |
| Team Yearly | `com.d2dadvancer.team3.yearly` | 1 year | USD 319.99 | New paywall |
| Legacy Weekly | `com.d2dadvancer.weekly` | 1 week | Existing App Store price | Existing subscribers |
| Legacy Yearly | `com.d2dadvancer.yearly` | 1 year | Existing App Store price | Existing subscribers |
| Legacy Monthly | `com.d2dadvancer.monthly` | 1 month | Existing App Store price | Recognition only |
| Legacy Team Monthly | `com.d2dadvancer.team.monthly` | 1 month | Existing App Store price | Recognition only |
| Legacy Team Yearly | `com.d2dadvancer.team.yearly` | 1 year | Existing App Store price | Recognition only |

App Store Connect checks:

- [x] All product IDs exactly match the app, StoreKit configuration, Cloud Functions, and App Store Connect.
- [x] Team products are a higher subscription level than Solo; monthly/yearly variants with equal access share a level.
- [x] Products are available in all 175 configured territories.
- [x] Prices and trial terms match the submitted build: monthly plans have no trial; yearly plans have a two-week trial.
- [x] Subscription localizations, review notes, and review screenshots are complete.
- [x] Paid Apps Agreement, Royal Bank of Canada payout account, and Canadian/U.S. tax forms are active. The current Paid Apps Agreement is effective through August 17, 2026.
- [x] All four new subscriptions are attached to the same review draft as version `1.3 (3)`.
- [ ] Purchase, restore, renewal-state, expiration, cancellation, and billing-retry behavior are tested with StoreKit sandbox/TestFlight.

## Store Listing

Suggested subtitle: `Field Sales & Team CRM`

Suggested keywords, subject to live 100-character validation:

`door to door,sales,leads,crm,field service,territory,appointments,follow up,team`

Use only screenshots captured from the submitted build. Show realistic non-sensitive sample data.

Recommended screenshot sequence:

1. Map with clustered leads and route controls.
2. Lead list with status and priority.
3. Simplified lead creation.
4. Lead details and follow-up workflow.
5. Appointments and technician dispatch.
6. Team workspace and assigned work.
7. Overview and performance summary.

- [x] Five 1290x2796 iPhone screenshots and five 2048x2732 iPad screenshots completed processing for version `1.3`.
- [ ] Verify screenshots contain no real customer names, addresses, phone numbers, or account data.
- [ ] Verify every claim in the description exists in the submitted build.
- [ ] Do not claim behavioral analytics, background GPS tracking, or "bank-level" encryption.

## URLs

- Support: `https://dan1sl6nd.github.io/D2D-Advancer/SUPPORT.html`
- Privacy policy: `https://dan1sl6nd.github.io/D2D-Advancer/PRIVACY_POLICY.html`
- Terms: `https://dan1sl6nd.github.io/D2D-Advancer/TERMS_OF_USE.html`

- [ ] Deploy the current `PRIVACY_POLICY.md` to the hosted privacy-policy URL. GitHub Pages publishes from `main`, which does not yet contain the July 18 Contacts-import disclosure.
- [x] All three public URLs returned HTTP 200 without a developer login on July 23, 2026.
- [x] The paywall and More screens point to these same current URLs.

## App Privacy Answers

Match App Store Connect answers to the app privacy manifest and hosted policy. Current app functionality may collect data linked to the user for App Functionality:

- Precise Location
- Physical Address
- Name
- Email Address
- Phone Number
- User ID
- Purchase History
- Photos or Videos
- Audio Data
- Other User Content
- Other Data

The app declares no cross-app tracking. Do not select Analytics for app-owned data unless analytics collection is intentionally added and verified in the submitted build.

- Firebase Auth and Firestore 12.1.0 also declare unlinked Other Diagnostic Data used for Analytics, with no tracking, in their embedded privacy manifests.

- [x] Confirm Firebase SDK privacy details against the exact embedded SDK versions.
- [x] Confirm 30-day Team duty-location retention is disclosed.
- [x] Confirm owner/member visibility and assigned-record privacy are disclosed.
- [x] Confirm Sign in with Apple and Firebase account deletion are described accurately.
- [x] App Store Connect now includes Other Diagnostic Data used for Analytics, not linked to identity, and not used for tracking. The original 11 linked App Functionality data types remain unchanged.

## Permissions and Review Notes

Optional permissions used by the app:

- When In Use Location: map centering, navigation, geocoding, and manual on-duty Team sharing.
- Calendar Full Access: create or update appointments when the user chooses.
- Contacts: save a selected lead to Contacts.
- Camera and Photo Library: attach selected property/job photos.
- Microphone and Speech Recognition: record and transcribe selected voice notes.
- Notifications: local appointment and follow-up reminders.

The release does not request Always Location permission.

Suggested review path:

1. Complete onboarding or use the supplied demo account.
2. Add, edit, and delete a lead.
3. Open the map and inspect clustering/filtering.
4. Create, edit, complete, and delete an appointment.
5. Set and complete a follow-up.
6. Open More > Account Management and verify in-app account deletion.
7. Open the paywall, view terms/privacy, purchase in sandbox, and restore purchases.
8. Use the supplied Team owner/worker test identities and invite code only if production Team testing is part of this submission.

- [ ] Provide a working reviewer account or a complete account-creation path.
- [ ] Provide any Team invite code and exact role-specific test steps.
- [ ] Explain that personal iCloud leads remain private and Team work uses Firebase.
- [ ] Explain that on-duty location sharing starts and stops manually.

## Local Engineering Gate

- [x] Clean Release archive, static analysis, App Store IPA export, and Transporter validation complete without blocking issues for version `1.3 (4)`.
- [x] Full unit-test target passes from a fresh result bundle (242 tests).
- [x] The broad 287-test run completed with 270 passes, 8 intentional skips, and 9 zero-duration UI-runner `SIGKILL` results rather than assertion failures. All nine affected scenarios passed focused reruns, including the dedicated seeded Apple Contacts import flow. Keep the original runner-pressure result bundle as evidence; do not describe it as an all-green monolithic run.
- [x] Firebase-emulator Team UI flow passes for owner, sales rep, and technician, including invites, duty state, lead creation, owner alerts, assignments, member details, and Team Field Map.
- [x] Current Team regression tests pass (63 Swift tests and 17 Cloud Functions tests).
- [x] Primary navigation and layout pass in light and dark mode.
- [x] iPad primary-navigation smoke tests pass in light and dark mode.
- [ ] Permission prompts and denied-permission states are tested.
- [ ] Account creation, Sign in with Apple, sign-out, and both deletion confirmation methods are tested.
- [x] Large lead dataset map/list performance is tested with 2,000 leads.
- [x] Team entitlement policy tests pass (6 tests).
- [x] Firebase rules and callable Team emulator end-to-end tests pass after server-authoritative billing changes (22 rules tests and 1 integration test).
- [x] Functions production dependency audit reviewed: no high or critical advisories; 8 moderate transitive advisories remain pending a supported Firebase SDK fix.
- [x] `PrivacyInfo.xcprivacy` is present in the archived app and validates.
- [x] Every app icon is opaque and the 1024x1024 marketing icon is present.
- [x] Generic-device Release archive succeeds for version `1.3 (4)`.
- [x] App Store Connect IPA export, server validation, and upload succeed for the current archive.
- [ ] Apple finishes processing build `1.3 (4)` and exposes it as a selectable build.

## Physical Device and TestFlight Gate

- [ ] Fresh install on the oldest supported iOS version available for testing.
- [ ] Fresh install and upgrade install on a current iPhone. The data-preserving build `1.3 (4)` upgrade passed on iPhone 17 and a post-install app-container backup confirmed 3,049 leads remained; a destructive fresh-install pass is not recorded.
- [ ] Camera, photo library, microphone, speech, Contacts, Calendar, notifications, and location prompts work without termination.
- [ ] Location centers reliably and stops Team sharing after Off duty.
- [ ] iCloud personal lead/appointment sync is verified between devices.
- [ ] Production Firebase Team owner/worker permissions are verified, unless Team is excluded from this release. The iPhone 17 passed production App Attest and reached strict callable input validation without a write; the full two-device owner/worker transaction remains unverified because Sofiia's iPhone was unavailable to Xcode.
- [ ] Purchase and restore are verified in TestFlight sandbox. Build `1.3 (3)` is in `Internal QA`, but its only App Store Connect user is disabled in the tester picker; add another eligible user with app access.
- [ ] Offline launch, edit queueing, reconnection, and conflict behavior are verified.
- [ ] No real customer data appears in screenshots, review accounts, or logs.

## Production and App Store Connect Gate

- [x] Production Firestore rules exactly match the tested 689-line repository rules; both normalized files have SHA-256 `94f4b2b61e4619ab85bb4480bf0cf7aaf1e3406a0a580585c392770fc51d5185`.
- [x] Production Firestore composite indexes match the three repository indexes. Production TTL policies are active for activity, duty-location, duty-session, notification, rate-limit, and usage-event expiry fields.
- [x] All six Firebase Cloud Functions report `ACTIVE`. The App Check-enforced `createTeamWorkspace` and `syncTeamEntitlement` callables share source hash `dfc862d7c4cc90056e33dc91c6318c79119463dd`; the other four functions were intentionally left unchanged. Credential-free production requests to both privileged callables returned HTTP 401 before any write, and all 17 local Functions tests passed against the deployed source.
- [x] Keep `firebase-functions` 7.2.5 for release 1.3. Version 7.3.0 adds extension-migration APIs unused by this backend and requires Firebase CLI 15.24.0 for those features; upgrade the SDK and the current 15.23.0 CLI together after release.
- [x] Production and Sandbox App Store Server Notifications V2 URLs point to the deployed notification function.
- [ ] An Apple-signed Sandbox notification reaches the function and updates the matching Team entitlement.
- [x] Firebase Authentication has Sign in with Apple enabled; Email/Password is also enabled for Team test identities.
- [x] The production Firebase project is on Blaze and all six deployed functions use the restricted `d2d-team-runtime` service account with bounded memory, concurrency, and instance counts.
- [x] The iOS app is registered with App Attest in Firebase App Check, an iPhone 17 build `1.3 (4)` produced a valid production token, and `D2D_ENFORCE_TEAM_APP_CHECK=true` was deployed to `createTeamWorkspace` and `syncTeamEntitlement`. The physical diagnostic reached strict callable input validation, while credential-free requests to both endpoints return HTTP 401.
- [ ] CloudKit production schema is deployed and query/index requirements are verified.
- [x] App Store Connect version metadata, age-rating questionnaire, content-rights answers, export compliance, privacy answers, and review contact are complete.
- [x] Uploaded build `1.3 (3)` remains selected and present in the five-item review draft.
- [x] Apple upload validation and transfer completed without blocking issues for build `1.3 (4)`.
- [ ] Apple processing completes and build `1.3 (4)` replaces build `1.3 (3)` in the review draft.
- [x] Version `1.3 (3)` and all four new subscriptions are explicitly added to one review draft.
- [ ] The five-item draft is submitted and its post-submission status is verified.

## Release Decision

The app is not ready to submit yet. The remaining release blockers are:

1. Merge the release branch to `main` so GitHub Pages publishes the current privacy disclosure.
2. Wait for Apple to finish processing build `1.3 (4)`, then attach it in place of build `1.3 (3)` without submitting the draft.
3. Validate purchase plus restore for Solo and Team on an Apple sandbox distribution surface.
4. Complete the remaining physical permission, iCloud sync, offline/reconnect, and two-device production Team checks that are applicable to this release.
5. Submit the five-item App Store review draft only after the gates above pass.
