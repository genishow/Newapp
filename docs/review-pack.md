# Kinbir: App Store review pack

Everything to paste into App Store Connect before pressing Submit. Apple ID 6835599193.

Order: 1 reviewer account, 2 description, 3 review notes, 4 screenshots, 5 last checks.

## 1. The reviewer account

Apple's reviewer cannot read your email, so they need an account with a fixed sign-in code.

1. On your phone, in the Kinbir app, sign in with a new email you can open (example: a second Gmail). This creates the account. It does not need a cloned voice: the built-in Kinbir voice works.
2. Send this to laptop Claude (put the email in):

```
Please set up the App Review account on the live server.
Email: PUT-THE-EMAIL-HERE
1. Give it 150 credits from the admin tools, note "App Review".
2. Give it a fixed six-digit sign-in code with POST /admin/review-login.
   Tell me the code once. Do not write it in any file.
3. Confirm: /auth/verify accepts that code for that email.
Do not deploy anything. Tell me in 3 lines.
```

3. Put the email and the six-digit code in App Store Connect, **App Review Information**, **Sign-in required**.
4. After approval, tell laptop Claude: "Remove the review sign-in code" (it sends `{"code": null}`).

Good to know: test purchases made by this account add credits, so the reviewer can buy a plan in Apple's test store and see it work. Other accounts get no credits from test purchases.

## 2. Description (paste into Version, Description)

```
Kinbir is an AI studio for Amharic and English videos.

Give it an idea, a link or your own words. Kinbir writes the script, reads it in a natural voice, and turns it into a finished video with footage, captions and music. No camera, no editing.

WHAT YOU CAN DO
• Write: turn an idea, an article link or rough notes into a script, in Amharic or English.
• Voice: hear it in the built-in Kinbir voice, or clone your own voice once and use it for everything.
• Speed: slower, normal or faster.
• Fix a word: tap any word that sounds wrong, hear other readings, or type how it should sound.
• Video: stock footage or your own clips, captions and music, vertical or horizontal.
• Presenter: an AI presenter made from your photo speaks your script on screen.
• Save to Photos or share to any app.

YOUR VOICE IS YOURS
A voice can only be cloned from a video of the person themself reading a consent statement. It is used only for your own projects. You can delete your account, voice and files from the app at any time.

CREDITS AND PLANS
New accounts start with free credits. Making voiceovers and videos uses credits. You can subscribe to get credits every month:
• Starter: 110 credits a month, $19.99 per month
• Pro: 325 credits a month, $49.99 per month
• Studio: 650 credits a month, $99.99 per month
• Top-up: 60 credits, $9.99, one time, no plan needed

Plans renew every month until you cancel. Payment is charged to your Apple Account at purchase, and the plan renews unless cancelled at least 24 hours before the end of the period. Manage or cancel in iPhone Settings, Apple Account, Subscriptions. Prices may differ by country.

For adults 18 and older.

Terms of Use: https://kinbir.com/terms
Privacy Policy: https://kinbir.com/privacy
Support: support@kinbir.com

ቅንብር የአማርኛና የእንግሊዝኛ ቪዲዮዎችን ያዘጋጃል። ሐሳብዎን ወይም ጽሑፍዎን ያስገቡ፤ ቅንብር ስክሪፕቱን ይጽፋል፣ በተፈጥሯዊ ድምፅ ያነባል፣ ከተስማሚ ቪዲዮዎች፣ ጽሑፎችና ሙዚቃ ጋር አቀናጅቶ ያዘጋጅልዎታል። የራስዎን ድምፅ አንድ ጊዜ በመቅረጽ ሁሉንም በራስዎ ድምፅ ማዘጋጀት ይችላሉ።
```

**What's New (first version):** `First release.`

## 3. Review notes (paste into App Review Information, Notes)

```
Thank you for reviewing Kinbir.

SIGN IN
Kinbir signs in with a code sent by email. For review, use the account in the sign-in fields above: enter the email, tap "Send me a code", then type the six-digit code given above. This review account accepts that code in place of an emailed one.

WHAT THE APP DOES
Kinbir turns text into a voiceover and then into a video. The fastest path to see it:
1. Sign in. Agree on the "How Kinbir uses AI" screen.
2. On Create, type one or two sentences (English is fine) and tap Generate. A voiceover is ready in about 30 to 60 seconds. If the servers are busy it can take a few minutes; a notification arrives when it is ready.
3. Tap "Make a video", pick Vertical, tap the button at the bottom. A short video is ready in a few minutes and can be saved to Photos.
The account has credits, so nothing needs to be bought to test.

VOICE CLONING AND CONSENT
A voice is cloned only from a video of the person themself, on camera, reading a consent statement aloud. The app asks for two explicit consents, and the server checks that the statement was really spoken before any voice is made. Cloning is optional: the built-in Kinbir voice works without it. The AI presenter uses a photo of the account holder with the same self-declaration.

AI CONTENT (5.1.2, 1.2)
Scripts are written by an AI writing service and the presenter video by an AI video service. The app says so and asks for agreement right after sign-in ("How Kinbir uses AI"). Under every result there is a "Report a problem with this result" link, and support@kinbir.com answers reports. Scripts, voices and videos are private to the account; there is no public feed, chat or sharing between users inside the app.

PURCHASES (3.1.1, 3.1.2)
Credits are sold only through In-App Purchase: Account, Buy credits. Three auto-renewing monthly subscriptions (Starter, Pro, Studio) and one consumable top-up that anyone can buy. The purchase screen shows the price, the period, the renewal terms, Restore Purchases, and links to the Terms and Privacy Policy. Credits bought as a top-up never expire. The review account can buy in the sandbox and will receive the credits.

ACCOUNT DELETION (5.1.1(v))
Account, Delete account. It deletes the account, the voice, and the files.

AGE
The app is for adults 18 and older; the sign-in screen says so and the age rating is set to match.

EARN CREDITS
Account, Earn credits: a user may send us a video they made about Kinbir and posted on their own social media. Each one is reviewed by a person; if approved, the user gets credits as a thank-you. It is optional, nothing in the app is locked behind it, and no rating or review of the app is asked for.

AVAILABILITY
The app is not offered in the European Union for now.

CONTACT
support@kinbir.com
```

## 4. Screenshots

Size: 6.9-inch iPhone, 1320 x 2868, at least 3, up to 10. Take them on your own phone with the real app (a Pro Max is the right size; other sizes are accepted only if they match a listed size, so tell Claude your phone model if it is not a Pro Max).

| # | Screen | What must be visible |
|---|---|---|
| 1 | Create, with an Amharic script typed | The script box and the Generate button |
| 2 | Voiceover ready | The player and the three speed buttons |
| 3 | Fix a word | A tapped word with the other readings |
| 4 | Shots page | Three or four shots with the Change buttons |
| 5 | A finished vertical video | The video playing, with captions |
| 6 | Presenter | The photo and the place picker |

Each plan and the top-up also need one **review screenshot** (not shown in the store): use one screenshot of the **Buy credits** screen for all four.

Rules that get screenshots rejected: no prices in the pictures, no other companies' names, and the pictures must be the real app.

## 5. Last checks before Submit

| Check | Where |
|---|---|
| App Privacy answers are published | App Store Connect, App Privacy |
| Paid Apps agreement, bank and tax show Active | Business |
| The build is picked on the version page | Version, Build |
| Each subscription and the top-up show "Ready to Submit" and are added to the version | Version, In-App Purchases and Subscriptions |
| Subscription group has a display name and each plan has a description | Monetization, Subscriptions |
| Privacy Policy URL and custom license (Terms) are set | App Information |
| Age rating 18+ | App Information |
| Push key is in the server (or pushes are simply off) | docs/app-store.md step 3 |
| Reviewer account signs in with the fixed code | Try it yourself on your phone first |
| Export compliance | Already answered in the app: no non-exempt encryption |

The first review usually takes 1 to 3 days. If Apple replies with a question or a rejection, paste their message to Claude.
