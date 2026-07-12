# Team Billing Rollout

## Compatibility contract

- Existing Team documents without `billingSource` are grandfathered. They keep their current members and data.
- Existing `com.d2dadvancer.weekly` and `com.d2dadvancer.yearly` subscribers remain valid Solo subscribers.
- Prior `com.d2dadvancer.monthly`, `com.d2dadvancer.team.monthly`, and `com.d2dadvancer.team.yearly` transactions remain recognized but hidden from new purchases.
- New Team workspaces require `com.d2dadvancer.team3.monthly` or `com.d2dadvancer.team3.yearly`.
- Expired Team plans are readable for seven days, with every Team write blocked. Reads stop after grace.
- No migration deletes personal Firebase data, private iCloud data, Team records, or App Store transactions.

## App Store Connect

Create these products in the existing Premium Access subscription group:

| Product ID | Display name | Period | Intended US price |
| --- | --- | --- | --- |
| `com.d2dadvancer.solo.monthly` | Solo Monthly | 1 month | $9.99 |
| `com.d2dadvancer.solo.yearly` | Solo Yearly | 1 year | $99.99 |
| `com.d2dadvancer.team3.monthly` | Team Monthly | 1 month | $29.99 |
| `com.d2dadvancer.team3.yearly` | Team Yearly | 1 year | $299.99 |

Keep all existing subscription products available to their current subscribers. Legacy products stay hidden from new purchases in the app.

Configure App Store Server Notifications V2 with the deployed HTTPS URL for `appStoreServerNotifications`. Use the same endpoint for Sandbox while validating the rollout.

## Deployment order

1. Create and approve the new App Store products.
2. Run `npm --prefix functions test` and `npm --prefix functions run build`.
3. Deploy Cloud Functions first: `firebase deploy --only functions`.
4. Ship the app version that creates teams through `createTeamWorkspace`.
5. Deploy `firestore.rules` after the new app is available. The final rules reject all client-created Team plan documents.
6. Test a Sandbox Team purchase, workspace creation, expiration/grace, renewal, and server notification before production rollout.

The functions verify Apple JWS signatures against Apple root certificates, bind an original transaction and app-account token to one Firebase owner, and write Team billing fields with the Admin SDK.
