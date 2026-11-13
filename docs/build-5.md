# Build 5: made easier to use

Everything from Builds 1 to 4 is kept. This build changes how the app looks, reads and
flows. It is based on a review of how CapCut, Captions, InVideo AI, Synthesia, HeyGen,
ElevenLabs, Speechify and Instagram Edits handle the same screens, and on Apple's interface
guidelines. Nothing here has run on a phone yet.

## In this build

| Screen | Change | Why |
|--------|--------|-----|
| First launch | Choose አማርኛ or English before anything else | Many diaspora phones are set to English, so the phone's setting is a poor guess |
| Whole app | Full Amharic interface, about 280 lines. Switch any time in Account | The first audience reads Amharic |
| Whole app | Space Grotesk, the Kinbir website typeface, with text that follows the phone's text size | One brand, and readable for everyone |
| Create | Idea chips on an empty screen: News, History, Motivation, Business, How to | Nobody should face an empty box |
| Create | "Write the script from this idea": type one line and Kinbir writes the full script | The top apps start from a prompt, not from finished text |
| Create | One-tap rewrites: Shorter, Longer, More dramatic, Simpler, Stronger opening. Undo still works | Faster than typing an instruction |
| Create | A notice when credits are nearly gone | No surprise at the worst moment |
| Voiceover wait | Named steps with ticks, a running clock and a usual time | People wait far more calmly when they can see where things are |
| Voiceover | Listening speed: 0.75x, 1x, 1.25x, 1.5x | Quick checking of long scripts |
| Make a video | "Make the video for me": plan, footage and render in one go. The step-by-step path is still there | One tap from voiceover to video |
| Planning and rendering waits | The same named steps, clock and usual time | Same reason |
| Change a shot | The clip in use plays on a loop at the top of the sheet | A still picture does not show what a clip is like |
| Clone my voice | The script stays on screen over the camera while recording | Before, the words disappeared when the camera opened |
| Library | "N h left" on items in their last 12 hours | Work is deleted after 48 hours, and people should know |
| Everywhere | A light buzz on success and failure, and on chips | Small, but it is what makes an app feel finished |

## Needs your review

- **The Amharic text.** I wrote it; a native speaker has not checked it. It is all in one
  file, `Sources/Support/Amharic.swift`, as English and Amharic side by side. Tell me any
  line that reads wrong and I will change it.
- **Messages from the server stay in English** for now, for example "insufficient credits".
  Translating them is a server change.
- **The "usual time" figures** (1 to 3 minutes for a voiceover, 2 to 5 for a video) are my
  estimates from your notes. Tell me what you actually see.

## Not in this build, and why

| Idea | What it needs |
|------|---------------|
| "Your video is ready" notification and a Lock Screen progress card | The server has to send it; an iPhone app cannot keep checking while closed |
| Real photos of named people in the footage | A server change in the footage search |
| A ready-made voice, so a new user needs no cloning | A server change (already agreed) |
| Buying credits with Apple | A server change and products in App Store Connect |
| A sample video on the first screen | A finished sample video from you |
| Caption style choices | I have not confirmed which styles the server offers |
| Direct "post to TikTok" buttons | Developer accounts with TikTok and Meta. The share sheet already offers those apps |
| A live sound meter while recording your voice | A custom camera screen, a larger job |
