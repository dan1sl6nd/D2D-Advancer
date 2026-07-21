# D2D Advancer Subscription Setup

Last updated: July 21, 2026

## Product model

All products belong to one App Store subscription group so a customer cannot accidentally hold Solo and Team at the same time.

| Level | Product ID | Reference name | Period | Intended US price |
| --- | --- | --- | --- | --- |
| 1 | `com.d2dadvancer.team3.yearly` | Team Yearly | 1 year | $299.99 |
| 1 | `com.d2dadvancer.team3.monthly` | Team Monthly | 1 month | $29.99 |
| 2 | `com.d2dadvancer.solo.yearly` | Solo Yearly | 1 year | $99.99 |
| 2 | `com.d2dadvancer.solo.monthly` | Solo Monthly | 1 month | $9.99 |

Team includes one owner plus two worker seats. A worker can be a sales rep or technician. Workers receive assigned Team work without buying their own Team subscription.

Annual Solo and Team products use a 14-day introductory free trial for eligible customers. Monthly products do not include an introductory trial. Apple limits each customer to one introductory offer across the entire subscription group, so the app only shows trial copy when StoreKit reports both a configured free-trial offer and current eligibility.

## Legacy products

Do not delete these existing products or remove entitlement recognition from the app:

- `com.d2dadvancer.weekly`
- `com.d2dadvancer.yearly`
- `com.d2dadvancer.monthly`
- `com.d2dadvancer.team.monthly`
- `com.d2dadvancer.team.yearly`

They stay hidden from the new paywall but remain recognized for any signed legacy, sandbox, TestFlight, or production transaction. The app prefers the new Solo Yearly product and falls back to the legacy yearly product while the new App Store products are being approved.

## App Store Connect setup

1. Open D2D Advancer, App ID `6751178741`.
2. Add the four new products to the existing subscription group.
3. Put both Team periods at the higher subscription level and both Solo periods at the lower level.
4. Add localization, review screenshots, tax category, territory availability, and pricing for every product.
5. Configure a two-week free introductory offer for `com.d2dadvancer.solo.yearly` and `com.d2dadvancer.team3.yearly` in every supported territory. Do not add a trial to either monthly product.
6. Keep the current weekly and yearly products available for existing subscribers, but do not present weekly to new customers in the app.
7. Configure App Store Server Notifications V2 using the deployed `appStoreServerNotifications` Cloud Function URL.

Apple's purchase sheet is the source of truth for localized price, taxes, renewal terms, and trial eligibility. Do not hard-code those claims into the paywall or legal pages.

With `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH` available in `.env.local`, audit live products without changing them:

```bash
node scripts/asc_d2d_subscriptions.mjs
```

After reviewing that audit, apply only the missing two-week annual trials with the explicit mutation flag:

```bash
node scripts/asc_d2d_subscriptions.mjs --apply-trials
```

The trial command is resumable and refuses to replace a conflicting current or future introductory offer.

## Backend enforcement

The app sends Apple's signed StoreKit transaction to Firebase callable functions. The backend:

- verifies the JWS against Apple root certificates;
- checks the bundle ID and App Store app ID;
- accepts only Team product IDs for Team creation;
- binds an original transaction and app-account token to one Firebase owner;
- ignores out-of-order transactions that are older than the latest verified renewal;
- creates Team billing fields with Firebase Admin; and
- applies active, seven-day read-only grace, or paused access.

Firestore rules reject Team creation from iPhone clients. Existing Team documents without `billingSource` are grandfathered so old Team data is adopted rather than invalidated.

## Rollout order

1. Create and approve the four new products.
2. Run `npm --prefix functions test` and `npm --prefix functions run build`.
3. Deploy Cloud Functions.
4. Configure and test App Store Server Notifications V2 in Sandbox.
5. Release app version `1.3 (2)` or higher.
6. Deploy the final Firestore rules that reject client-created teams.
7. Test purchase, restore, Solo-to-Team upgrade, Team-to-Solo downgrade, renewal, expiration, refund, grace, and account deletion.

## Sandbox acceptance checks

- A new Solo purchase unlocks personal lead, map, Work, and iCloud features.
- A legacy yearly or weekly entitlement still unlocks Solo.
- A Team purchase unlocks Solo features and permits one Team workspace.
- One Team transaction cannot create workspaces for two Firebase owners.
- The owner can invite exactly two workers under the included three-seat limit.
- Expiration blocks edits while preserving seven days of reads.
- Renewal restores Team access without deleting members, leads, jobs, or activity.
- Restore Purchases works after reinstall with the same Apple and Team identity.
- Team restore does not unlock workspace creation until Firebase confirms the transaction belongs to the signed-in owner.

See `docs/team-billing-rollout.md` for deployment and compatibility details.
