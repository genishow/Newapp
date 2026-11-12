# Build 2: server changes

Build 1 uses the Kinbir server exactly as it runs today. Build 2 needs three server changes.
This file is the design. The server code itself is **not written yet**: it lives in the
`kinbir` repo, has to be deployed from the owner's PC with `scripts/deploy-api.ps1`, and
needs the Apple product IDs to exist first.

## 1. Buying credits with Apple

Apple requires in-app purchase for credits sold inside an iPhone app.

### In App Store Connect (owner)

Create these products for `com.geni.kinbir`:

| Product ID | Type | Credits | Mirrors |
|------------|------|---------|---------|
| `kinbir.topup60` | consumable | 60 | the website $10 top-up |
| `kinbir.starter.monthly` | auto-renewing subscription | 110 a month | Starter |
| `kinbir.pro.monthly` | auto-renewing subscription | 325 a month | Pro |
| `kinbir.studio.monthly` | auto-renewing subscription | 650 a month | Studio |

Prices need rechecking against Apple's 15% cut before they are set.

### New endpoint: `POST /billing/apple`

- Body: `{access_code, signed_transaction}` where `signed_transaction` is the StoreKit 2
  JWS string the app receives after a purchase.
- The server verifies the JWS signature against Apple's root certificate, and checks
  `bundleId == "com.geni.kinbir"` and that the product ID is one of the four above.
- Credits are granted once per `transactionId`, recorded in the same processed-grants file
  the Stripe webhook uses, so a retry never grants twice.
- Consumable: add the credits with `credit_adjust(code, +N, "apple_topup", ref=transactionId)`.
- Subscription: set the tier and monthly allowance the same way `grant-tier` does, and add
  the month's credits. Renewals arrive through App Store Server Notifications.
- Answer: `{credits_granted, credits_balance, tier}`.

### New endpoint: `POST /apple/notifications`

- Receives App Store Server Notifications V2 (renewal, cancellation, refund).
- Renewal: grant the next month's credits once per `transactionId`.
- Refund: remove the granted credits, never below zero.

### In the app

- A "Get credits" screen using StoreKit 2 `Product.products(for:)` and `purchase()`.
- After a verified purchase, the app posts the transaction to `/billing/apple`, then calls
  `transaction.finish()` only after the server confirms.
- On launch, `Transaction.unfinished` is replayed to the server, so a purchase that was
  interrupted is never lost.
- A "Restore purchases" button, which Apple requires.

## 2. The built-in voice for new users

Agreed with the owner on 2026-11-12: new users may make full voiceovers in the built-in
Kinbir voice without cloning first.

- `POST /generate`: when the account has no voice, use `DEMO_VOICE` instead of answering
  400 "clone your voice first". Charge credits as normal.
- `GET /whoami`: add `"builtin_voice": true` so the app can show "Kinbir voice" in the
  voice line and offer "Clone my own voice" as the upgrade.
- The built-in voice is never listed under the account's own voices and cannot be renamed
  or deleted.

## 3. A small free taste for app sign-ups

Today free credits arrive only after a voice is enrolled (20 credits, about a dollar of
cost). With the built-in voice, a new account needs credits at sign-in.

- `POST /auth/verify`: when `is_new` is true and the request carries `"client": "ios"`,
  grant 3 credits once per account (about one 60 second voiceover).
- Keep the existing once-per-account rule so deleting and re-creating an account does not
  grant again for the same email.
- The 20 credit grant after enrollment stays as it is for the website. For app accounts it
  is replaced by the 3 credit grant.

## Order of work

1. Owner creates the products in App Store Connect.
2. Server changes written in the `kinbir` repo, with tests beside the existing ones.
3. Owner deploys with `scripts/deploy-api.ps1`.
4. App Build 2 adds the Get credits screen and the built-in voice line.
