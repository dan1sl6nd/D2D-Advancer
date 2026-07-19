---
layout: default
title: Privacy Policy - D2D Advancer
description: Privacy Policy for the D2D Advancer iOS app
---

# Privacy Policy for D2D Advancer

**Effective date:** July 12, 2026

**Last updated:** July 18, 2026

D2D Advancer ("we," "our," or "us") is a field-sales and service-work management app. This policy explains what information the app handles, why it is used, where it is stored, and the choices available to you.

We do not sell personal information and do not use personal information for cross-app tracking.

## Information the App Handles

### Account and identity information

When you create or join a Team workspace, the app may process your name, email address, Firebase user identifier, Sign in with Apple credential, and Team role. Passwords for email accounts are handled by Firebase Authentication and are not stored by D2D Advancer in readable form.

### Lead, customer, and job information

The app stores information that you enter about leads, customers, appointments, and service jobs. This may include names, phone numbers, email addresses, physical addresses, notes, status, quoted prices, service details, follow-up dates, arrival windows, assigned workers, and activity history.

When you choose **More > Apple Contacts > Scan This iPhone**, the app checks accessible contact name, company, department, and job-title fields on your device for the service phrases shown in the import screen. For matching contacts, the app also reads the available phone, email, and postal-address fields needed to prepare a lead. Direct iPhone scans do not read contact notes.

If you separately run the D2D Advancer Mac Contacts export helper, macOS asks you to approve access to the Contacts app. The helper writes a local JSON file containing only contacts that match the supported service phrases, including their contact fields, notes, and any price recognized from those notes. The file is not uploaded by the helper. The iOS app reads it only after you choose **Import Mac Export** and select the file. Nothing is copied into D2D Advancer until you review and select a match. Selected contacts create new personal workspace leads or safely fill missing details on matching leads; existing app notes and nonzero prices are preserved. These leads follow the same local and optional iCloud storage rules described below.

You are responsible for having an appropriate business reason and any required consent before entering another person's information.

### Photos, voice notes, and transcripts

If you choose these features, the app can attach photos to leads, record voice notes, and create speech-recognition transcripts. The app requests camera, photo-library, microphone, and speech-recognition access only when the related feature is used.

### Location information

With permission, the app uses precise location while it is open to center the map, show nearby work, geocode selected map points, and provide navigation.

For Team members, location is shared with authorized Team users only after the member manually selects **On duty**. Sharing stops when the member selects **Off duty**. Team duty routes and location points are retained for up to 30 days and are then scheduled for deletion. Members can view their own active-hours route; Team owners can view routes for their Team. Other members cannot view one another's routes.

The current release does not request Always Location permission and does not perform continuous background location tracking.

### Subscription information

Purchases and subscriptions are processed by Apple through StoreKit. For Team plans, Apple's signed transaction identifier, product identifier, expiration status, and an app-account token are linked to the Firebase Team owner so the backend can verify access, prevent one purchase from being reused by another account, and apply the read-only grace period. We do not receive or store your full payment-card details.

### Diagnostics and attribution

The app and its service providers may process basic technical information needed to operate, secure, and troubleshoot the service. D2D Advancer does not include its own third-party behavioral analytics or advertising-tracking system. Apple may provide App Store attribution information under Apple's terms.

## How Information Is Used

We use information to:

- provide lead, map, follow-up, appointment, and Team features;
- authenticate users and enforce Team permissions;
- synchronize data between a user's devices;
- assign leads and jobs to authorized Team members;
- share on-duty location with the authorized Team users described above;
- deliver local reminders selected by the user;
- verify Solo and Team subscription entitlements;
- secure, maintain, and troubleshoot the app.

## Where Information Is Stored

### Private personal workspace

Personal leads and appointments are stored locally using Apple's Core Data technologies. When iCloud sync is enabled, personal workspace data is stored in the user's private Apple CloudKit/iCloud database. Personal leads are not automatically moved into a Team workspace.

### Team workspace

Team identity, membership, assigned Team leads and jobs, activity records, on-duty location records, and Team entitlement records are stored using Google Firebase Authentication, Cloud Firestore, and Cloud Functions. Access is restricted by authenticated user identity, Team role, assignment rules, and server-verified plan state.

### On-device storage

The app stores settings, cached records, and other data required for offline use on the device. Authentication secrets and saved credentials use Apple Keychain where applicable.

Data is transmitted using encrypted network connections provided by Apple, Google Firebase, and the operating system.

## Sharing and Service Providers

We disclose information only as needed to operate the app, when you direct us to share it, or when required by law.

- **Apple:** iCloud/CloudKit, Sign in with Apple, MapKit and geocoding, StoreKit, app distribution, and operating-system services.
- **Google Firebase:** Team authentication, Team workspace database services, and server-side Team entitlement verification.
- **Authorized Team users:** Team owners can view Team records and on-duty member location. Workers can view only work assigned to them, their own active-hours route, and the owner's on-duty location where enabled.

We may disclose information when reasonably necessary to comply with law, protect users, investigate abuse, or protect the rights and security of D2D Advancer.

## Retention

- Personal workspace data remains on the device and, when enabled, in the user's private iCloud storage until the user deletes it or removes the app's iCloud data.
- Team account information is retained while the Team identity is active.
- Team subscription bindings and transaction identifiers are retained as needed to verify access, prevent entitlement reuse, process renewals or refunds, and meet legal or accounting obligations.
- On-duty Team location points and route sessions are retained for up to 30 days.
- Local reminders remain until completed, cancelled, or removed under the app's reminder settings.
- A worker's shared Team work records may remain in the Team owner's workspace after the worker leaves or deletes their Team identity because those records are part of the owner's business workflow. The deleted worker no longer has Team access.

## Your Choices and Rights

Within the app, you can view and update account information, edit or delete leads and appointments, change notification and sync preferences, leave or close a Team, and turn location access off in iOS Settings.

### Account deletion

Go to **More > Account Management > Delete Account** to delete your Team identity. Email accounts confirm with their password. Sign in with Apple accounts confirm with Apple; the app then revokes the Apple authorization token and deletes the Firebase account and personal Firebase account records.

Deleting a Team identity does not delete the separate personal workspace stored in your private iCloud account. Personal data can be deleted through the app's data-management controls or by removing D2D Advancer data from iCloud settings.

For access, correction, deletion, or portability questions that cannot be completed in the app, contact us using the address below. We may need to verify the request before acting on it.

## Notifications and Device Permissions

The app uses local notifications for reminders. You can change notification access in iOS Settings. Camera, photo-library, contacts, calendar, microphone, speech-recognition, and location permissions are optional and are requested when their associated features are used. Denying a permission limits only the related feature.

## Children

D2D Advancer is a business productivity app and is not directed to children under 13. We do not knowingly collect personal information from children under 13.

## International Processing

Apple and Google may process information in countries other than your own, subject to their contractual and legal safeguards.

## Changes to This Policy

We may update this policy as the app or legal requirements change. We will update the date above and provide additional notice when required.

## Contact

For privacy questions or requests, contact:

**D2D Advancer**

**Email:** [dan1sl6nd@gmail.com](mailto:dan1sl6nd@gmail.com)

Copyright 2026 D2D Advancer.
