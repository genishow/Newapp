# Putting Kinbir on the App Store

Everything the app needs is built. What is left is Apple paperwork, done once.
Steps marked **(Claude)** are things to hand to Claude; the rest happen on Apple's websites.

## 1. Join the Apple Developer Program ($99 a year)

1. Go to https://developer.apple.com/programs/enroll and enroll with your Apple ID.
2. Wait for the approval email (usually 1 to 2 days).
3. While waiting, join the **Small Business Program** later (step 9) so Apple keeps 15% instead of 30%.

## 2. Create the app in App Store Connect

1. https://appstoreconnect.apple.com, **Apps**, **+**, **New App**.
2. Platform iOS, name **Kinbir**, primary language **English (U.S.)**, bundle ID **com.geni.kinbir**, SKU `kinbir-ios`.
3. Open **App Information** and copy the **Apple ID** number (about 10 digits). Send it to Claude **(Claude)**: it goes into the server as `APPLE_APP_ID` so live purchases are accepted. TestFlight purchases work before this.
4. Still in App Information, under **App Store Server Notifications**, set both the Production and Sandbox URL to
   `https://api.kinbir.com/billing/apple/notifications` and choose **Version 2**.

## 3. Turn on push for the app

1. https://developer.apple.com/account/resources/identifiers, open **com.geni.kinbir**, tick **Push Notifications**, Save.
2. **Keys**, **+**, name it `Kinbir push`, tick **Apple Push Notifications service (APNs)**, Continue, Register, **Download** the `.p8` file (only downloadable once). Note the **Key ID** and your **Team ID** (top right of the page).
3. On your PC, in the kinbir folder, store it in Modal (the key never goes into chat or code):
   ```
   python -m modal secret create apns --force APNS_KEY_ID=YOURKEYID APNS_TEAM_ID=YOURTEAMID APNS_KEY_P8="$(Get-Content -Raw C:\path\to\AuthKey_YOURKEYID.p8)"
   ```
   Then redeploy the API (`.\scripts\deploy-api.ps1`). Until this is done, pushes are simply off.

## 4. Create the products

In App Store Connect, open Kinbir, **Monetization**.

**Subscriptions**: create a group named `Kinbir plans`, then three auto-renewable subscriptions, 1 month each:

| Product ID | Reference name | Price (US) | Display name | Description |
|---|---|---|---|---|
| com.geni.kinbir.starter.monthly | Starter monthly | $19.99 | Starter | 110 credits every month |
| com.geni.kinbir.creator.monthly | Pro monthly | $49.99 | Pro | 325 credits every month |
| com.geni.kinbir.studio.monthly | Studio monthly | $99.99 | Studio | 650 credits every month |

Order them in the group Studio, Pro, Starter (highest first), so Apple treats moving up as an upgrade.

**In-App Purchases**: one **Consumable**:

| Product ID | Reference name | Price (US) | Display name | Description |
|---|---|---|---|---|
| com.geni.kinbir.topup60 | Top-up 60 | $9.99 | Top-up | 60 credits, once |

Each product needs a review screenshot: use a screenshot of the Buy credits screen.

The product IDs must match exactly; the server and app look for these names.

## 5. TestFlight secrets **(Claude)**

The upload job is `.github/workflows/testflight.yml` (fastlane, `fastlane/Fastfile`). It needs these GitHub secrets on the Newapp repo:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (an App Store Connect API key, Users and Access, Integrations, Team Keys, role App Manager), `APPLE_TEAM_ID`, `MATCH_GIT_URL` (a new empty private repo for signing certificates), `MATCH_PASSWORD` (any long password you keep), `MATCH_GIT_BASIC_AUTHORIZATION` (base64 of `githubuser:token` with access to that repo), `BUNDLE_ID` = `com.geni.kinbir`.
Ask Claude to walk you through each one. Then run **Actions**, **TestFlight (optional, paid)**, **Run workflow**.

## 6. Test on TestFlight

1. In App Store Connect, **Users and Access**, **Sandbox**, add a sandbox tester (a new email you control).
2. Install the TestFlight build from the TestFlight app.
3. Check: buy Starter (sandbox, no real money), credits arrive; Restore purchases; make a voiceover, leave the app, the "ready" notification arrives; save a video to Photos; delete account wording.
4. Sandbox renewals happen every 5 minutes for a monthly plan, so renewals can be watched in an hour.

## 7. The listing

**Name (30):** Kinbir: Amharic AI Video Maker
**Subtitle (30):** Voice clone & text to speech
**Primary language:** English (U.S.). App Store Connect has no Amharic listing language, and the Amharic audience on iPhone is mostly outside Ethiopia. Amharic goes in the screenshots and in the description's second half.
**Category:** Photo & Video (secondary: Productivity)
**Age rating:** the app is for adults: sign-in says "You must be 18 or older", and cloning a voice or face needs an adult's consent. In the age questionnaire answer no to violence, mature content, gambling and unrestricted web access, then under **Age Assurance / override** choose the highest rating offered (**18+**, or 17+ where 18+ is not offered). A 4+ rating next to an "18 or older" sign-in screen gets rejected. User-generated content: No, scripts stay private to the account.
**Price:** Free (with in-app purchases)
**Support URL:** https://kinbir.com (support email: support@kinbir.com)
**Availability:** every country except the 27 European Union countries, so no home address has to be shown (EU law makes Apple show a seller's address and phone there). Add the EU later with a business address or P.O. box.
**Privacy Policy URL:** https://kinbir.com/privacy
**Terms (EULA):** add https://kinbir.com/terms in the description's last line and in App Information, License Agreement, custom.

**Promotional text (170):**
AI writes your script, your cloned voice reads it, and Kinbir cuts the video: footage, captions, music and your AI presenter. Amharic and English.

**Description:**
Kinbir is an AI studio for Amharic and English videos, in your own voice.

Give it an idea, a link or your own words. Kinbir's AI writes the script, reads it in a voice cloned from you, and turns it into a finished video with footage, captions, music and an AI presenter of you. No camera, no editing.

Record a short video of yourself reading a statement once. Kinbir learns your voice, and from then on everything is in your voice.

- AI script writing: turn an idea, an article link or rough notes into a script, in Amharic or English.
- Pick the speed: slower, normal or faster.
- Fix any word that sounds wrong by tapping it, hearing other readings, or typing how it should sound, in English letters or Amharic.
- Turn the voiceover into a video with stock footage or your own clips, music and captions, vertical or horizontal.
- Add your AI presenter: an avatar made from your photo speaks the script on screen.
- AI smart edit: camera moves, scene changes and caption highlights planned for you.
- Save to Photos or share straight to any app.

Your voice is yours. Kinbir only clones a voice from a recording of the person themself, with their consent, and it is never used for anything but your own projects. Delete your account, voice and files at any time from the app.

Plans renew monthly until cancelled in your iPhone Settings. Terms: https://kinbir.com/terms

**Description in Amharic (add Amharic later only if App Store Connect offers it for the region; otherwise keep it at the end of the English one):**
ቅንብር በራስዎ ድምፅ የድምፅ ቅጂ ይሠራል። አንድ ጊዜ ስክሪፕት ሲያነቡ ይቅረጹ፤ ከዚያ በኋላ የሚጽፉትን ማንኛውንም ስክሪፕት በአማርኛ ወይም በእንግሊዝኛ በራስዎ ድምፅ ያነባል። የተሳሳተ ቃል ካለ ነክተው ያስተካክሉ፣ ወደ ቪዲዮ ይቀይሩ፣ በፎቶዎች ያስቀምጡ ወይም ያጋሩ።

**Keywords (100):** ethiopia,ethiopian,habesha,voiceover,tts,reels,shorts,caption,avatar,generator,script,አማርኛ,ቅንብር
(No word from the name or subtitle is repeated: Apple already searches those. No other companies' names: Apple can reject for that.)

**Screenshots** (6.9-inch iPhone, 1320 x 2868; at least 3): the Create page with a script, the voiceover player with the speed buttons, the word fix screen, a finished vertical video, the Buy credits screen is not needed. Take them on a 16 Pro Max or Pro Max size, or ask Claude to produce them from the simulator **(Claude)**.

## 8. App Privacy answers (App Store Connect, App Privacy)

Data collected, all **linked to the user**, **not used for tracking**:

| Type | Used for |
|---|---|
| Contact info: Email address | App functionality (sign in) |
| User content: Audio data (voice recording) | App functionality |
| User content: Photos or videos (enrollment video, uploaded clips, presenter photo) | App functionality |
| User content: Other user content (scripts) | App functionality |
| Identifiers: Device ID (push token, and an app-made phone ID that stops repeat free gifts) | App functionality |
| Identifiers: User ID (the account) | App functionality |
| Purchases: Purchase history | App functionality |
| Usage data: Product interaction | Analytics |

Tracking: **No**. Third-party advertising: **No**.

## 9. Small Business Program

https://developer.apple.com/app-store/small-business-program, enroll once the paid account is active. Apple's cut drops from 30% to 15%.

## 10. Review notes (App Review Information)

Sign-in required: yes. Kinbir signs in with a code sent by email, so give the reviewer a ready account:

- Make a reviewer account with credits and a voice already enrolled, then give it a fixed sign-in code with `POST /admin/review-login` (admin only; only one account, removed after approval) **(Claude)**.
- Contact: your name, phone, support@kinbir.com.

Before submitting, also check:
- **AI data sharing (rule 5.1.2(i)).** After sign-in the app shows "How Kinbir uses AI" and needs "I agree" before anything is made; the Privacy Policy lists the same providers by kind. Nothing to do, just know it is there if the reviewer asks.
- **Credits (rule 3.1.1).** Bought top-up credits never expire; only the monthly plan allowance is capped at renewal.
- **iPad.** The app is iPhone-only, but Apple also opens it on an iPad in iPhone size. Open the TestFlight build on an iPad once if you can borrow one.
- **Paid Apps agreement, tax and bank forms** in App Store Connect, Business: purchases do not load for the reviewer until these are Active.
- **Screenshots must show the real app**, and one must show the Buy credits screen for the in-app purchase review.

Notes text:
> Kinbir creates voiceovers in the user's own cloned voice. A voice can only be made from a video of the person themself reading a consent statement and a script; enrollment asks for two explicit consents and every voice is checked before use.
> Sign in: enter the email below, tap Send code, then type the 6-digit code below (this review account accepts it instead of an emailed code).
> AI: scripts are written by an AI writing service, the presenter video by an AI video service; the app shows this and asks for agreement right after sign-in ("How Kinbir uses AI"). The voice clone and presenter need the person's own consent and a self-declaration, and a "Report a problem with this result" link is under every result.
> The account already has an enrolled voice and credits, so you can write a script and press Generate (about 30 seconds). Credits are bought through In-App Purchase (Account, Buy credits). Notifications tell the user when a voiceover or video is ready.

## 11. Submit

Pick the TestFlight build in the version page, answer export compliance (already set: no non-exempt encryption), and **Submit for Review**. First reviews take 1 to 3 days. If they reply, paste their message to Claude.
