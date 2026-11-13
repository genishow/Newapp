# Build 8: polish, and checks that run without a Mac

Small, safe improvements on top of Build 7. Not compiled or run on an iPhone yet.

## What changed in the app

| Where | Before | Now |
|-------|--------|-----|
| Amharic text | Headings fell back to the phone's own Amharic font, which looked thinner than the English | Noto Sans Ethiopic ships inside the app in three weights, so Amharic headings and buttons are as strong as English ones |
| Credits | A number at the top with no explanation | Tap the number: a sheet shows the balance, what each thing costs, and what is free |
| Empty Library | A grey box with two lines | A round lime icon, a title and one line |
| Library rows | Text only | Each row starts with a round icon: play, sound bars, or film |
| First screen | **Start free** scrolled away on small phones | Pinned at the bottom |
| Sign in | **Send a new code** was greyed out with no reason | It shows the seconds left |

## What changed in testing

- `scripts/check_linux.sh` runs the checks that need no Mac: every file parses, the 83 logic
  tests pass, and the Amharic table has a line for every string. It needs Docker.
- The end-to-end tests now keep a picture of every screen. GitHub saves them as an artifact
  called `screenshots-N`, so the screens can be reviewed without a phone.
- While the repository is public (free minutes), every push runs the full tests. While it is
  private, a push only builds the app, as before.

## Honest limits

- The screens have not been compiled since Build 6. Build 7 and Build 8 will be compiled for
  the first time on the next GitHub run. Expect one or two rounds of fixes.
- Still needs the server: Apple purchases, the built-in voice for new users, Library
  thumbnails, caption timing, push notifications.
