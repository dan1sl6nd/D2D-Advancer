# D2D Advancer Release Readiness Gates

Use this checklist before a TestFlight or App Store build. Do not treat one green gate as proof for another.

## Code Health

- `git diff --check` passes.
- App builds with the shared scheme.
- Unit tests pass for the full `D2D AdvancerTests` target.
- High-noise diagnostics in recently touched paths use `AppLog` or `#if DEBUG`.

## Map Workflow

- Launch centers on the user's current location without fighting pinch or pan gestures.
- Long-press lead creation uses the closest resolved street address, not a coordinate fallback.
- Map filters apply immediately for All, Hot, Due, Today, Sold, and Next.
- Clusters open a detail sheet or expand before the user has to zoom into house-level detail.
- Sold leads appear before Interested leads, and Interested leads appear before ordinary open work.

## Team Workspace

- Team health shows one clear state: online, refreshing, saving, offline, or blocked.
- Cached Team visibility is not treated as proof that Firebase is healthy.
- Owner can create/cancel invites, remove members, close the workspace, and refresh Team.
- Sales reps and technicians can leave a Team from their own device.
- Rep-created important work notifies the owner only when it becomes interested, booked, converted, or high priority.

## Data Safety

- Lead delete, appointment delete, quick action undo, member removal, invite cancel, worker leave, and owner close all require deliberate user action.
- Deleted appointments and leads do not reappear from sync after local removal.
- Offline/pending Team edits recover or show a clear failure message.

## UI Proof

- Smoke the primary tabs in light and dark mode.
- Smoke More child screens in light mode to catch black navigation chrome regressions.
- Smoke Team Workspace in owner and worker states.
- Capture screenshots for any UI fix that depends on runtime geometry.

## Backend And Device Proof

- Firebase rules/emulator tests pass before live Firebase claims.
- Simulator UI tests do not count as two-phone proof.
- Physical owner/rep or owner/technician tests are required before claiming real Team reliability.
