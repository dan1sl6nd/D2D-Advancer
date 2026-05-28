# Hybrid Team Workspaces Design

## Summary

D2D Advancer will add a small-team workspace for owner-led teams of 2-5 reps. The first version uses a hybrid storage model:

- Personal workspace data stays private and continues using the existing local/Core Data/iCloud sync direction.
- Team workspace data uses Firebase so the app can enforce team membership, role-based access, assignment visibility, invite expiry, subscription gating, notifications, and live location writes.

The v1 business model is a Team plan with the owner plus 2 reps included. Extra-seat billing is out of scope for v1.

## Goals

- Let a team owner invite up to 2 reps with single-use invite links that expire after 7 days.
- Keep existing personal leads private when a user joins a team.
- Let reps create team leads, automatically assigned to themselves.
- Let reps see only their assigned team leads, bookings, owner instructions, and their own active-hours GPS graphs.
- Let the owner see and manage all team records.
- Notify the owner only when a lead becomes important.
- Add manual On duty / Off duty location sharing with 30-day active-hours GPS graph retention.
- Enforce Team plan lifecycle: active, 7-day read-only grace, then paused until renewal.

## Non-Goals

- Multiple teams per user.
- Reps browsing all team leads.
- Rep-to-rep location visibility.
- Long-term GPS retention beyond 30 days.
- Territory drawing or dispatcher-grade routing.
- Threaded team chat.
- Extra-seat billing.
- Automatic import of existing personal leads into a team.

## Existing App Context

The app already has personal field-workflow surfaces: leads, follow-up check-ins, bookings, maps, route planning, attachments, templates, and notification behavior. Prior sync work moved the app toward iCloud-first personal sync while keeping Firebase available for account and legacy sync surfaces.

That makes a hybrid model preferable for v1. Personal records do not need a new backend permission model. Team records do, because assignment visibility and owner-only management must be enforced server-side, not just hidden in SwiftUI.

## Roles

### Owner

- Creates the team.
- Holds the Team subscription.
- Generates and revokes invite links.
- Reads and writes all team leads, bookings, owner instructions, activity records, and duty sessions.
- Assigns and reassigns leads.
- Removes members.
- Views active live locations and active-hours GPS graphs for all reps.

### Member

- Joins through a valid invite link.
- Creates team leads that auto-assign to their own user id.
- Reads and edits only assigned team leads and related bookings.
- Reads owner instructions on assigned leads.
- Sends one short structured reply/status to each owner instruction.
- Starts and stops their own duty sessions.
- Views only their own active-hours GPS graph.

## Workspace Model

Each account can have:

- One personal workspace.
- Zero or one team workspace.

The app must make the active workspace explicit in navigation. Personal records and team records should not be mixed in one implicit list. Joining a team does not import, copy, or expose existing personal leads.

New leads created in the team workspace are team records. New leads created in the personal workspace remain personal records.

## Team Subscription Model

The Team plan includes:

- 1 owner.
- 2 reps.
- 3 total team members.

Reps do not need individual paid subscriptions while they are members of an active Team plan. Team access is controlled by team membership and the owner's subscription state.

Team subscription states:

- `active`: team reads and writes are allowed.
- `grace`: 7-day read-only grace after expiration.
- `paused`: team workspace access is paused after grace until renewal.

During `grace`, block all team edits:

- No creating leads.
- No editing lead status.
- No completing, cancelling, or rescheduling bookings.
- No invite links.
- No owner instructions.
- No high-priority changes.
- No On duty sessions or GPS writes.

Renewal restores access without deleting team data.

## Firebase Data Model

Use Firebase for team objects only. Exact field names can be adapted during implementation, but the schema should preserve these boundaries.

### `teams/{teamId}`

- `name`
- `ownerUserId`
- `createdAt`
- `updatedAt`
- `planStatus`: `active`, `grace`, or `paused`
- `planExpiresAt`
- `graceEndsAt`
- `memberLimit`: 3

### `teams/{teamId}/members/{userId}`

- `userId`
- `displayName`
- `email`
- `role`: `owner` or `member`
- `status`: `active` or `removed`
- `joinedAt`
- `removedAt`

### `teamInvites/{inviteId}`

- `teamId`
- `createdByUserId`
- `defaultRole`: `member`
- `createdAt`
- `expiresAt`
- `revokedAt`
- `consumedAt`
- `acceptedByUserId`

Invite links are single-use, expire after 7 days, and become invalid after acceptance.

### `teams/{teamId}/leads/{leadId}`

- Lead contact, address, status, service category, price/estimated value, notes, tags, priority, photos, voice-note metadata, and location fields needed for team use.
- `createdByUserId`
- `assignedToUserId`
- `updatedByUserId`
- `createdAt`
- `updatedAt`
- `isHighPriority`
- `highPriorityReason`

Rep-created leads must set `assignedToUserId` to the current user at creation time.

### `teams/{teamId}/bookings/{bookingId}`

- `leadId`
- `assignedToUserId`
- title, notes, start date, end date, location, type, status, calendar-event metadata if applicable.
- `createdByUserId`
- `updatedByUserId`
- `createdAt`
- `updatedAt`

Rep-created bookings must be for leads already assigned to that rep.

### `teams/{teamId}/ownerInstructions/{instructionId}`

- `leadId`
- `assignedToUserId`
- `text`
- `createdByUserId`
- `updatedByUserId`
- `createdAt`
- `updatedAt`
- `repStatus`: `none`, `done`, `customer_not_home`, `needs_owner_follow_up`, or `could_not_complete`
- `repNote`
- `repRespondedAt`

This is not a chat system. V1 stores the current instruction and one structured rep response.

### `teams/{teamId}/dutySessions/{sessionId}`

- `repUserId`
- `startedAt`
- `endedAt`
- `status`: `active` or `ended`
- `lastLocationAt`
- `distanceMeters`
- `createdAt`
- `deleteAfter`: ended timestamp plus 30 days

### `teams/{teamId}/dutySessions/{sessionId}/points/{pointId}`

- `repUserId`
- `latitude`
- `longitude`
- `horizontalAccuracy`
- `recordedAt`
- `deleteAfter`: recorded timestamp plus 30 days

GPS points are recorded only while the rep is On duty. They must be deleted automatically after 30 days.

### `teams/{teamId}/activityLog/{activityId}`

- `actorUserId`
- `targetUserId`
- `leadId`
- `bookingId`
- `instructionId`
- `type`
- `message`
- `createdAt`

Location-free activity events can remain longer than GPS points. Example: `Mike went off duty at 4:12 PM` should not include coordinates.

## Permission Rules

Permissions must be enforced in Firebase rules and service-layer checks.

Owner:

- Can read and write all team documents when plan status is `active`.
- Can read all team documents during `grace`.
- Cannot write during `grace`.
- Cannot access team workspace during `paused`, except enough metadata to renew or show the paused state.

Member:

- Can read assigned leads.
- Can write assigned leads while plan status is `active`, except reassignment and owner-only fields.
- Can read and write bookings tied to assigned leads while plan status is `active`.
- Can read owner instructions for assigned leads.
- Can write only the structured reply fields on assigned owner instructions.
- Can create duty sessions for their own user id while plan status is `active`.
- Can read their own duty sessions and points.
- Cannot read other reps' leads, bookings, instructions, live dots, or GPS graphs.

Everyone:

- Existing personal workspace records are never controlled by team Firebase rules.
- Removed members immediately lose team access.
- Invitation acceptance must fail if the invite is expired, revoked, consumed, or the team is already full.

## Lead Flow

### Rep Creates Team Lead

1. Rep is in the team workspace.
2. Rep creates a lead.
3. App writes the lead with `createdByUserId = currentUserId` and `assignedToUserId = currentUserId`.
4. Rep can view and edit that lead.
5. Owner can view and manage that lead.
6. Other reps cannot see it.

### Owner Creates Team Lead

1. Owner creates a lead.
2. Owner can assign it to a rep or leave it unassigned.
3. Assigned rep gets a notification.
4. Unassigned leads are owner-visible only.

### Reassignment

Only the owner can reassign a lead. When reassigned:

- The old rep loses access immediately.
- The new rep gains access.
- Future scheduled bookings for that lead automatically move to the new assignee.
- Completed and cancelled bookings keep their historical assignee.

## Booking Flow

- Reps can schedule bookings only for leads assigned to them.
- Rep-created bookings inherit `assignedToUserId` from the lead.
- Owner can view and manage all bookings.
- Reps see their own bookings in the team calendar.
- Owner sees the full team calendar.
- The app should warn about overlapping bookings for the same assigned rep.

## Important Lead Notifications

The owner should not be notified for normal lead creation, ordinary edits, notes, or attachments.

Notify the owner when:

- A lead is marked interested.
- A follow-up-needed status is set.
- A booking is scheduled or confirmed.
- A lead is marked converted.
- A rep turns on High Priority.
- A booked or confirmed appointment is cancelled or rescheduled.

High Priority is manual:

- Rep can mark an assigned lead High Priority.
- Rep can add a short reason.
- Owner is notified only when the flag changes from off to on.
- Owner can clear or edit priority on any lead.
- Rep can clear priority only for assigned leads.

## Owner Instructions

Owner instructions are separate from regular lead notes.

- Owner can add or update instructions on any team lead.
- Assigned rep can see instructions on that lead.
- Rep receives a notification when instructions are added or updated.
- Rep can set one status: Done, Customer not home, Needs owner follow-up, or Could not complete.
- Rep can add one short note with that status.
- Owner receives a notification when the rep replies.

V1 should not implement threaded chat.

## Live Location and Active-Hours Graph

Location sharing is manual for v1.

### On Duty

- Rep taps On duty.
- App starts a duty session.
- App records GPS samples only for that active session.
- Owner sees the rep's live dot.
- Owner can view active-hours route graph.
- Rep can view their own graph.

### Off Duty

- Rep taps Off duty.
- App ends the duty session.
- Rep live dot disappears immediately from the owner map.
- Activity log records the off-duty event without coordinates.
- Owner can still view the completed active-hours graph for 30 days.

### Retention

- Raw GPS points and route graphs are retained for 30 days.
- After 30 days, GPS points and graph data are auto-deleted.
- Owner cannot override retention in v1.
- Reps can view only their own 30-day route history.
- Reps cannot view other reps' live location or GPS graphs.

The UI should clearly show reps when location sharing is active and explain that active-hours route data is visible to the owner while On duty.

## UI Surfaces

### Workspace Switcher

- Shows Personal and the team workspace name when available.
- Makes the active workspace obvious.
- Prevents personal/team record mixing.

### Team Settings

Owner:

- Team name.
- Member list.
- Invite Rep.
- Revoke pending invites.
- Remove member.
- Plan status.

Member:

- Team name.
- Owner name.
- Own membership state.
- Leave team, which removes team workspace access while preserving the member's personal workspace.

### Lead List

Owner filters:

- All.
- Unassigned.
- High Priority.
- By rep.
- Follow-ups.

Rep filters:

- Mine.
- Today.
- Follow-ups.
- High Priority.

### Lead Detail

- Assignment state.
- High Priority button.
- Owner Instructions section.
- Rep instruction status reply.
- Team-visible notes and attachments.

### Calendar

Owner:

- Full team calendar.
- Filter by rep.

Rep:

- Assigned bookings only.

### Team Map

Owner:

- Assigned lead pins.
- Today bookings.
- On-duty rep live dots.
- Rep active-hours graph.

Rep:

- Own assigned lead pins.
- Own bookings.
- Own active-hours graph.
- No other rep live dots.

## Error Handling

- Expired invite: show that the invite expired and ask the rep to request a new one.
- Consumed invite: show that the invite was already used.
- Full team: prevent acceptance and tell the owner the Team plan supports owner plus 2 reps in v1.
- Removed member: immediately sign out of team workspace and show personal workspace.
- Grace state write attempt: show read-only grace message.
- Paused state: show renewal-required message for owner and unavailable-team message for reps.
- Location permission denied: On duty cannot start; show location permission recovery steps.
- Network unavailable during team write: queue only if rules can still enforce current user/team ownership; otherwise fail visibly and let the user retry.

## Testing Plan

- Unit-test role and plan-state permission helpers.
- Unit-test invite validity: active, expired, revoked, consumed, team full.
- Unit-test assignment visibility: owner all records, rep assigned only, removed member none.
- Unit-test read-only grace gating for lead, booking, instruction, invite, and duty-session writes.
- Unit-test high-priority notification trigger fires only on off-to-on transition.
- Unit-test GPS retention date calculation.
- Integration-test Firebase rules with owner, assigned rep, unassigned rep, removed rep, and unauthenticated user.
- UI-test workspace switching so personal records do not appear in team lists.
- UI-test rep lead creation auto-assigns to the rep.
- UI-test On duty / Off duty: live dot appears, disappears, and graph remains viewable for 30-day window.

## Rollout Plan

1. Add team domain models and service protocols without changing existing personal workspace behavior.
2. Add Firebase collections and security rules for teams, members, invites, leads, bookings, instructions, activity, and duty sessions.
3. Add Team plan entitlement state and action gating.
4. Add team creation and invite acceptance.
5. Add workspace switcher.
6. Add team lead list/detail with assignment visibility.
7. Add team bookings.
8. Add owner instructions and high-priority notification triggers.
9. Add manual On duty / Off duty live location and 30-day retention cleanup.
10. Add owner dashboard/map surfaces.
11. Run Firebase rules tests, Swift unit tests, and simulator UI checks.

## Implementation Decisions

- Team leads use separate Firebase DTOs mapped into SwiftUI view models for v1. They do not reuse the personal Core Data `Lead` entity as a local cache.
- Team bookings use a separate Firebase `TeamBooking` DTO behind a team booking repository. They do not write into the current personal `AppointmentManager` Codable storage.
- Cloud Functions or scheduled cleanup should delete expired invite records and GPS points older than 30 days.
- App Store privacy labels and privacy policy must be updated before shipping live location and active-hours graph features.
