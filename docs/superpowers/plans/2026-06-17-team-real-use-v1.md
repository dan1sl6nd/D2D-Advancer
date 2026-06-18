# Team Real-Use V1 Plan

## Scope

Build the repo-owned parts of ten Team Workspace functions that can be compiled and tested locally:

1. Owner can reassign team leads between active reps.
2. Owner can reassign team bookings between active reps.
3. Reps can send one short status reply on assigned work.
4. Team activity log records important owner/rep actions.
5. Duplicate team lead detection catches same phone, same address, or nearby homes.
6. Owner can remove active reps and free the seat.
7. Owner can mark alert records read.
8. Owner and rep get "today work" summaries.
9. Grace/paused plans block every team write path.
10. Offline/pending writes have explicit display state instead of silent failure.

## Out of Scope For Local Proof

APNs push delivery, App Store subscription renewal state, Firebase production provider config, and two physical iPhones cannot be proven from Xcode unit tests alone. The app-side hooks should compile, but production validation still needs the real Firebase project, Apple services, and two-device smoke testing.

## Verification

- Add deterministic Swift tests in `D2D AdvancerTests/TeamWorkspaceTests.swift`.
- Update Firestore rules tests where new collections or write paths exist.
- Run targeted Swift tests.
- Run Firestore emulator rules tests if the local emulator is available.
- Build the app on an iOS simulator.
