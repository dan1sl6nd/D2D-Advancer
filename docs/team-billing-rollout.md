# Team Billing Rollout

## Compatibility contract

- Existing Team documents without `billingSource` are grandfathered. They keep their current members and data.
- Existing `com.d2dadvancer.weekly` and `com.d2dadvancer.yearly` subscribers remain valid Solo subscribers.
- New Team workspaces require `com.d2dadvancer.team.monthly` or `com.d2dadvancer.team.yearly`.
- Expired Team plans are readable for seven days, with every Team write blocked. Reads stop after grace.
- No migration deletes personal Firebase data, private iCloud data, Team records, or App Store transactions.

## App Store Connect

Create these products in the existing Premium Access subscription group:

| Product ID | Display name | Period |
| --- | --- | --- |
| `com.d2dadvancer.monthly` | Solo Monthly | 1 month |
| `com.d2dadvancer.team.monthly` | Team Monthly | 1 month |
| `com.d2dadvancer.team.yearly` | Team Yearly | 1 year |

Keep `com.d2dadvancer.yearly` and `com.d2dadvancer.weekly` active for existing customers. The weekly product stays hidden from new purchases in the app.

Configure App Store Server Notifications V2 with the deployed HTTPS URL for `appStoreServerNotifications`. Use the same endpoint for Sandbox while validating the rollout.

## Deployment order

1. Create and approve the new App Store products.
2. Run `npm --prefix functions test` and `npm --prefix functions run build`.
3. Deploy Cloud Functions first: `firebase deploy --only functions`.
4. Ship the app version that creates teams through `createTeamWorkspace`.
5. Deploy `firestore.rules` after the new app is available. The final rules reject all client-created Team plan documents.
6. Test a Sandbox Team purchase, workspace creation, expiration/grace, renewal, and server notification before production rollout.

The functions verify Apple JWS signatures against Apple root certificates, bind an original transaction and app-account token to one Firebase owner, and write Team billing fields with the Admin SDK.
