# D2D Advancer App Store Release Checklist

Last audited: July 10, 2026

This file separates local engineering proof from App Store Connect and production-service proof. Do not mark an item complete based on simulator evidence alone.

## Product Identity

- App Store app ID: `6738387157`
- Bundle ID: `dan1sland.D2D-Advancer`
- Developer Team ID: `RF247ARQB7`
- Current marketing version: `1.1`
- Current project build number: `1`
- Minimum iOS version: `18.5`
- Category: Business

Before uploading, confirm in App Store Connect that build number `1` has not already been used for version `1.1`. Increment it in Xcode if it has.

## Toolchain Requirement

Apple requires iOS submissions to be built with Xcode 26 or later and the iOS 26 SDK as of April 28, 2026. The release audit used Xcode 26.6. Recheck Apple's upcoming requirements page immediately before upload.

## Subscription Products

Subscription group: `Premium Access`

| Product | Product ID | Duration | Local StoreKit price | Trial |
| --- | --- | --- | --- | --- |
| Weekly Plan | `com.d2dadvancer.weekly` | 1 week | USD 9.99 | 3 days |
| Yearly Plan | `com.d2dadvancer.yearly` | 1 year | USD 36.99 | None |

App Store Connect checks:

- [ ] Both product IDs exactly match the app and StoreKit configuration.
- [ ] Products are available in the intended territories.
- [ ] Prices and trial terms match the paywall shown in the submitted build.
- [ ] Subscription localizations are complete and within App Store Connect limits.
- [ ] Paid Applications agreement, tax, and banking status are active.
- [ ] Both subscriptions are attached to the version submitted for review when required.
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

- [ ] Confirm required iPhone and iPad screenshot slots on the live version page.
- [ ] Verify screenshots contain no real customer names, addresses, phone numbers, or account data.
- [ ] Verify every claim in the description exists in the submitted build.
- [ ] Do not claim behavioral analytics, background GPS tracking, or "bank-level" encryption.

## URLs

- Support: `https://dan1sl6nd.github.io/D2D-Advancer/SUPPORT.html`
- Privacy policy: `https://dan1sl6nd.github.io/D2D-Advancer/PRIVACY_POLICY.html`
- Terms: `https://dan1sl6nd.github.io/D2D-Advancer/TERMS_OF_USE.html`

- [ ] Deploy the current `PRIVACY_POLICY.md` to the hosted privacy-policy URL.
- [ ] Open every URL from a device without a developer login and confirm HTTP 200 plus readable mobile layout.
- [ ] Confirm the in-app links point to the same current pages.

## App Privacy Answers

Match App Store Connect answers to the app privacy manifest and hosted policy. Current app functionality may collect data linked to the user for App Functionality:

- Precise Location
- Physical Address
- Name
- Email Address
- Phone Number
- User ID
- Photos or Videos
- Audio Data
- Other User Content
- Other Data

The app declares no cross-app tracking. Do not select Analytics for app-owned data unless analytics collection is intentionally added and verified in the submitted build.

- [ ] Confirm Firebase SDK privacy details against the exact embedded SDK versions.
- [ ] Confirm 30-day Team duty-location retention is disclosed.
- [ ] Confirm owner/member visibility and assigned-record privacy are disclosed.
- [ ] Confirm Sign in with Apple and Firebase account deletion are described accurately.

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

- [x] Clean Release build and static analysis complete with zero errors and reviewed warnings.
- [x] Full unit-test target passes from a fresh result bundle (175 tests).
- [x] Serial UI smoke suite passes on a current iPhone simulator (21 broad passes plus the repaired onboarding flow rerun).
- [x] Primary navigation and layout pass in light and dark mode.
- [x] iPad primary-navigation smoke tests pass in light and dark mode.
- [ ] Permission prompts and denied-permission states are tested.
- [ ] Account creation, Sign in with Apple, sign-out, and both deletion confirmation methods are tested.
- [x] Large lead dataset map/list performance is tested with 2,000 leads.
- [x] Firebase rules tests (21) and Team emulator end-to-end test pass.
- [x] `PrivacyInfo.xcprivacy` is present in the exported app and validates.
- [x] Every app icon is opaque and the 1024x1024 marketing icon is present.
- [x] Generic-device Release archive succeeds.
- [x] App Store Connect IPA export succeeds with Cloud Managed Apple Distribution signing.

## Physical Device and TestFlight Gate

- [ ] Fresh install on the oldest supported iOS version available for testing.
- [ ] Fresh install and upgrade install on a current iPhone.
- [ ] Camera, photo library, microphone, speech, Contacts, Calendar, notifications, and location prompts work without termination.
- [ ] Location centers reliably and stops Team sharing after Off duty.
- [ ] iCloud personal lead/appointment sync is verified between devices.
- [ ] Production Firebase Team owner/worker permissions are verified, unless Team is excluded from this release.
- [ ] Purchase and restore are verified in TestFlight sandbox.
- [ ] Offline launch, edit queueing, reconnection, and conflict behavior are verified.
- [ ] No real customer data appears in screenshots, review accounts, or logs.

## Production and App Store Connect Gate

- [ ] Production Firestore rules match the tested repository rules.
- [ ] Firebase Authentication has Sign in with Apple enabled and configured for the production bundle.
- [ ] CloudKit production schema is deployed and query/index requirements are verified.
- [ ] App Store Connect version metadata, age-rating questionnaire, content-rights answers, export compliance, privacy answers, and review contact are complete.
- [ ] Correct uploaded build is selected.
- [ ] Automated App Store Connect validation has no blocking issues.
- [ ] Version is explicitly added for review and its status is verified after submission.

## Release Decision

The app is ready to submit only when every applicable local, physical-device/TestFlight, production-service, and App Store Connect item above has current evidence. A passing simulator build alone is not a release decision.
