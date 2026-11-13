# Build 6: working the way the website works

After the owner tested Build 4 on her phone, the website's own code was studied screen by
screen and these parts of the app were rebuilt to match it. Not compiled or run yet.

## What was wrong and what changed

| What you saw | Cause | Change |
|--------------|-------|--------|
| Hearing one word's reading took very long | The app waited 2 seconds before every check, even when the reading was ready at once. It also prepared nothing ahead and never woke the voice engine | The first reading now plays by itself when you tap a word. The others are prepared in the background. A reading that already exists plays immediately, and one you heard once replays instantly. The voice engine is woken as soon as the voiceover opens |
| Fixing one word took a long time and cost 1.5 credits each | The app recorded again after every single choice | The website's way: choosing a reading only adds it to a list. One button, "Generate my N changes · 1.5 credits", records them all together. There is a Stop button that returns the credits |
| Editing a sentence was hard | The app only had "read the sentence again", hidden inside the word screen | Two modes on the voiceover, as on the website: "Fix how a word sounds" and "Change the words". In the second, tap a sentence to edit its words or record it again |
| An item appeared in the Library and said "expired" | The server's list holds every kind of job: script writing, footage plans and renders, not only voiceovers. The app listed them all, and those have no audio | The Library now shows only real voiceovers, plus videos from the video list |
| A long silence after starting a voiceover | A bare spinner | The website's screen: "Composing your voiceover", which part is being voiced, a progress bar, the voice in use, a running clock, and a notice after three minutes that it is still working |
| The first voiceover of a session is slow | The voice engine takes about two minutes to wake | The app now wakes it as soon as there is a script and a voice, before you press the button |
| The script page was hard to understand | One box that guessed what you meant | The website's three numbered steps. Step 1 "Your script" with four clear choices: Amharic text, Ask Kinbir, English text, Article link. Step 2 "Your voice". Step 3 "Make the voiceover" |
| Things from the website were missing | Not built yet | Added: "Close to the original" style next to "Video style", the permission tick for article links, the reading-time counter, the price on the write and voiceover buttons, and "Your recent scripts" from any device |
| Video screens did not match the format | The player and pictures were a fixed shape | The player, shot pictures, clip choices and previews now follow vertical or horizontal |

## Captions that look slightly behind

This is on the server, not in the app. The server shows one word at a time and works out
each word's moment by its length in letters. It does not listen for where each word really
falls, so a word can show a little early or late. It is the same at every quality. Fixing
it means aligning the captions to the audio on the server. Please check whether the same
video made on the website shows the same lag, to confirm.

## Still simpler than the website

- Editing or re-recording applies to a whole block of the script, where the website can
  target one sentence inside a block.
- "Say it yourself" (record the word so Kinbir matches it) is not in the app yet.
- The Ethiopic letter palette is not needed: the iPhone has an Amharic keyboard.
- The video is made at 1080p. The website's default is 4K, which takes longer.
