# Install Kinbir on your iPhone (SideStore)

This is the same free path you used for FourShot. You need SideStore already set up on your
iPhone. If it is not, follow Step 3 of the FourShot setup guide first.

## Step 1: Download Kinbir.ipa from GitHub

1. Open the `Newapp` repo on GitHub and click the **Actions** tab.
2. Click the newest run of **CI** that has a **green tick**.
   - Yellow dot means it is still building. Wait and refresh.
   - Red X means it failed. Screenshot it and send it to Claude.
3. Scroll to the bottom to **Artifacts**. Click **Kinbir-build-NUMBER** to download it.
4. It downloads as a `.zip`. Unzip it. Inside is **Kinbir.ipa**.
5. Put Kinbir.ipa on your iPhone:
   - On your PC, go to https://www.icloud.com/iclouddrive, sign in, and drag **Kinbir.ipa** in.
   - On your iPhone it shows in the **Files** app under **iCloud Drive**.

Tip: you can do all of Step 1 on your iPhone in Safari. The zip lands in **Files**, then
**Downloads**. Tap it once to unzip.

## Step 2: Install with SideStore

1. On your iPhone, open **LocalDevVPN** and tap **Connect**.
2. Open **SideStore** and go to **My Apps**.
3. Tap the **+** in the top left.
4. Choose **Kinbir.ipa** from Files.
5. Wait until Kinbir appears in the list. This takes about a minute.

## Good to know

- A free Apple ID can have **3 sideloaded apps** active at once. SideStore is one, FourShot
  may be another, Kinbir is the third. If SideStore says you are at the limit, remove one
  first.
- Sideloaded apps **stop opening after 7 days** unless you refresh them in SideStore.
- Installing a newer build replaces the old one. You stay signed in.

## Later: TestFlight

When you want TestFlight, add the same 8 secrets FourShot uses to the `Newapp` repo
(Settings, Secrets and variables, Actions), with `BUNDLE_ID` set to `com.geni.kinbir`, and
create the app in App Store Connect with that bundle ID. Then run the **TestFlight** workflow
from the Actions tab.
