# Subscription Setup Guide for D2D Advancer

This guide walks you through setting up in-app subscriptions using StoreKit 2.

## ✅ What's Already Done

- ✅ PaywallManager.swift implemented with full StoreKit 2
- ✅ PaywallView.swift with professional UI
- ✅ Lead tracking and paywall triggering
- ✅ Configuration.storekit file for local testing

## 📋 Steps to Complete Setup

### 1. App Store Connect Setup

#### A. Create Your App (if not already done)
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click "My Apps" → "+" → "New App"
3. Fill in app information:
   - Platform: iOS
   - Name: D2D Advancer
   - Primary Language: English
   - Bundle ID: **Must match your Xcode Bundle ID exactly**
   - SKU: Any unique identifier (e.g., `d2d-advancer-2025`)

#### B. Create Subscription Group
1. In your app → Click "Features" tab
2. Click "In-App Purchases" section
3. Click "+" next to "Subscription Groups"
4. Name: `Premium Access` (or similar)
5. Click "Create"

#### C. Create Subscriptions

**Weekly Subscription:**
1. Inside your subscription group, click "+"
2. Select "Auto-Renewable Subscription"
3. Fill in:
   - **Reference Name**: Weekly Premium
   - **Product ID**: `com.d2dadvancer.weekly` (must match PaywallManager.swift)
   - **Subscription Duration**: 1 Week

4. Subscription Prices:
   - Click "Add Pricing"
   - Select all territories
   - Price: **$9.99 USD**

5. **Add Free Trial**:
   - Scroll to "Subscription Offers"
   - Click "Create Introductory Offer"
   - Type: Free
   - Duration: 3 Days
   - One time offer

6. Localization (English - U.S.):
   - Display Name: `Weekly Plan`
   - Description: `Get unlimited leads with our weekly subscription. Includes 3-day free trial.`

**Yearly Subscription:**
1. Click "+" to add another subscription
2. Fill in:
   - **Reference Name**: Yearly Premium
   - **Product ID**: `com.d2dadvancer.yearly` (must match PaywallManager.swift)
   - **Subscription Duration**: 1 Year

3. Subscription Prices:
   - Price: **$36.99 USD**

4. Localization (English - U.S.):
   - Display Name: `Yearly Plan`
   - Description: `Best value! Get unlimited leads for a full year. Save 93% compared to weekly.`

#### D. App Review Information (Required)
For each subscription, you need to provide:
1. **Screenshot**: Take a screenshot of the PaywallView showing the subscription
2. **Review Notes**: Explain how to trigger the paywall
   ```
   To test subscriptions:
   1. Launch the app (no login required - guest mode)
   2. Tap the "+" button to add leads
   3. After adding 10 leads, the paywall will appear
   4. Select a plan and purchase

   Test credentials are not needed (guest mode enabled).
   ```

### 2. Xcode Configuration

#### A. Enable In-App Purchase Capability
1. Open your Xcode project
2. Select your target → "Signing & Capabilities"
3. Click "+ Capability"
4. Add "In-App Purchase"

#### B. Configure StoreKit Testing
1. In Xcode, go to Product → Scheme → Edit Scheme
2. Select "Run" → "Options" tab
3. Under "StoreKit Configuration", select "Configuration.storekit"
4. This lets you test purchases without real money

#### C. Update Product IDs (if needed)
In `PaywallManager.swift` (lines 21-22), verify these match your App Store Connect product IDs:
```swift
private let weeklyProductID = "com.d2dadvancer.weekly"
private let yearlyProductID = "com.d2dadvancer.yearly"
```

### 3. Testing with Sandbox

#### A. Create Sandbox Tester Account
1. App Store Connect → Users and Access
2. Sandbox Testers → "+" button
3. Create test account (use fake but valid-format email)
4. **Important**: Use a different country than your real Apple ID to avoid conflicts

#### B. Test on Device
1. Sign out of App Store on your test device (Settings → App Store → Sign Out)
2. Build and run your app from Xcode
3. Add 10 leads to trigger paywall
4. Attempt a purchase
5. When prompted, sign in with your sandbox tester account
6. Complete test purchase (won't charge real money)

#### C. Test Scenarios
- ✅ Free trial starts correctly (weekly plan)
- ✅ Purchase completes successfully
- ✅ Premium features unlock
- ✅ Restore purchases works
- ✅ Subscription auto-renews (accelerated in sandbox)
- ✅ Cancellation works

### 4. Production Checklist

Before submitting to App Review:

- [ ] All subscription metadata filled in App Store Connect
- [ ] Screenshots and review notes provided
- [ ] Tested with sandbox account
- [ ] Privacy policy mentions subscriptions
- [ ] App binary includes In-App Purchase capability
- [ ] Subscription terms clearly displayed in app
- [ ] Auto-renewal notice in UI (already in PaywallView)
- [ ] Restore purchases button visible (already in PaywallView)

### 5. Important Legal Requirements

Your app already includes these (in PaywallView.swift):
- ✅ Price clearly displayed
- ✅ Subscription duration shown
- ✅ Auto-renewal disclosure
- ✅ Cancellation instructions
- ✅ Free trial terms (for weekly)
- ✅ Restore purchases option

### 6. Monitoring & Analytics

After launch, monitor in App Store Connect:
- Sales and Trends → Subscriptions
- Track:
  - New subscriptions
  - Renewals
  - Cancellations
  - Trial conversions
  - Revenue

## 🧪 Local Testing (No App Store Connect Needed)

For development, use the included `Configuration.storekit` file:

1. In Xcode: Product → Scheme → Edit Scheme → Run → Options
2. Select "Configuration.storekit" under StoreKit Configuration
3. Build and run
4. Purchases will be simulated locally
5. **Note**: Actual transactions only work with real App Store products

## 🔧 Troubleshooting

**Products not loading?**
- Verify Bundle ID matches App Store Connect
- Check product IDs are identical in code and App Store Connect
- Products must be "Ready to Submit" status
- Wait 15 minutes after creating products for them to propagate

**Sandbox purchases failing?**
- Sign out of real App Store account on device
- Use sandbox tester account created in App Store Connect
- Check sandbox account hasn't been used on too many devices (max 10)

**"Cannot connect to iTunes Store" error?**
- Normal in Simulator (use StoreKit configuration instead)
- On device: Check internet connection
- Verify sandbox tester email/password

**Subscription not recognized after purchase?**
- Check Transaction.currentEntitlements in PaywallManager
- Verify transaction is being finished
- Look for verification errors in console

## 📞 Support Resources

- [Apple In-App Purchase Documentation](https://developer.apple.com/in-app-purchase/)
- [StoreKit 2 Guide](https://developer.apple.com/documentation/storekit)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)

## 🎯 Quick Reference

**Product IDs (Update if needed):**
- Weekly: `com.d2dadvancer.weekly`
- Yearly: `com.d2dadvancer.yearly`

**Pricing:**
- Weekly: $9.99/week with 3-day free trial
- Yearly: $36.99/year (no trial)

**Free Lead Limit:** 10 leads

**Files Modified:**
- `PaywallManager.swift` - Purchase logic
- `PaywallView.swift` - UI
- `Configuration.storekit` - Local testing
