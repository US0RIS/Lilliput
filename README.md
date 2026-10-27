# Lilliput

**A tiny pixel-art construction crew that lives on your Mac and treats your real windows as buildings.**

Open a window and a crew walks in from the edge of the screen, plants a sign, drops a stack of planks and starts putting up scaffolding along its bottom edge and sides. Drag the window and they brace themselves while the crane hook swings. Resize it and they wobble, then carry in more planks or take sections down. Minimize it and they pack up in a puff of dust; close it and they dismantle everything and head home. Left alone, they hammer, inspect blueprints, climb ladders, take breaks, and now and then do something worth noticing.

Lilliput has no productivity purpose. It runs entirely on your Mac, makes no network connections, and never reads window contents.

## Install

1. Download `Lilliput.zip` from the `lilliput-build` artifact of the latest successful [Build workflow run](https://github.com/US0RIS/Lilliput/actions/workflows/build.yml) (sign in to GitHub; the artifact zip contains `Lilliput.zip`). Tagged versions (`v*`) are also published on the [Releases](https://github.com/US0RIS/Lilliput/releases) page.
2. Unzip and move **Lilliput.app** to `/Applications`.
3. The build is ad-hoc signed (no Apple Developer ID), so Gatekeeper blocks the first launch. Either right-click the app → **Open** → **Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Lilliput.app
   ```
4. Launch it. A hard-hat icon appears in the menu bar; there is no Dock icon.

Requires macOS 15 or later. Universal binary (Apple silicon and Intel).

## Accessibility permission

Lilliput needs **Accessibility** access to follow other apps' windows: where they are, how big they are, and when they open, move, resize, minimize or close. That is all it uses it for.

- On first launch an onboarding window explains this. Click **Grant Access** (shows the macOS prompt once) or **Open System Settings** and switch on Lilliput under *Privacy & Security → Accessibility*. Lilliput notices the change on its own; **Retry** forces a re-check.
- **Screen Recording is not requested.** Window geometry comes from the window server's public window list, which needs no capture permission, and Lilliput never reads titles or pixels.
- Without permission, **Demo Mode** still works (menu → *Demo Construction…*).
- Because builds are ad-hoc signed, macOS treats every rebuild as a new app. After installing a new build, remove the old Lilliput entry in the Accessibility list and add the new one.

## Using it

Menu-bar menu:

| Item | What it does |
|---|---|
| Enable / Disable Lilliput | Removes or restores all overlays and window observation |
| Pause Workers | Freezes the crew in place (scaffolding still follows windows) |
| Construction Density | Sparse (deck + one tower), Normal (both towers, rails, pulley), Busy (taller towers, crane, more crew) |
| Worker Size | Small / Normal / Large: 18 / 21 / 24 pt tall |
| Animation Intensity | Subtle / Balanced / Playful: frequency of special events, reaction size, idle frame rate |
| Special Events | Toggle the occasional little moments |
| Sound Effects | Quiet synthesized hammer taps and clunks (off by default) |
| Start a Special Event Now | Skip the wait |
| Demo Construction… | Opens the demo window |
| Settings… | Full settings (⌘,) |

**Settings** also has: launch at login, show over full-screen apps (off by default, so video and presentations stay clean), maximum simultaneous sites (1–12, default 6), maximum workers per site (1–6, default 4), and an excluded-apps list (add a running app or choose any app bundle). All settings persist and apply to the live crew immediately.

### Demo Mode

A separate window with pretend windows, driven by the *same* simulation code as the real overlays. Buttons: Open, Move, Fling (fast drag), Resize, Focus (reorder), Minimize, Restore, Close, Event, plus **Autoplay**. Works without Accessibility permission. Launch straight into it with `Lilliput.app/Contents/MacOS/Lilliput --demo` (or `--demo-autoplay`).

### Things to look for

Two workers carrying one long plank in step · a hammer dropped from a tower, fetched and brought back up · the crane lowering its hook while a worker signals · a nap on a platform ended by a colleague · a knocked-over plank stack, tidied up · the white-hat supervisor walking the site with a clipboard and giving a thumbs-up · two workers disagreeing over a blueprint · a celebration and a flag on the tower when a site is first finished · someone nearly losing their footing when you resize · a worker hanging on during a fast fling.

## Build from source

```sh
git clone https://github.com/US0RIS/Lilliput.git
cd Lilliput
open Lilliput.xcodeproj          # or:
xcodebuild -project Lilliput.xcodeproj -scheme Lilliput -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build
open build/Build/Products/Release/Lilliput.app
```

Run the tests:

```sh
xcodebuild -project Lilliput.xcodeproj -scheme Lilliput -destination 'platform=macOS' test
```

Set `TEST_RUNNER_LILLIPUT_ART_OUT=/path/sheet.png` to have the test run export a contact sheet of every sprite.

Xcode 16 or later. No third-party dependencies. All art is drawn in code (`Lilliput/Art`); the app icon PNGs were generated from the same palette.

CI (`.github/workflows/build.yml`) runs on every push: Debug build + unit tests, universal Release build, ad-hoc signing check, and a 70-second smoke launch of Demo Mode autoplay with screenshots, all uploaded as the `lilliput-build` artifact. Pushing a `v*` tag publishes a GitHub release with the zipped app.

## How it works

See [ARCHITECTURE.md](ARCHITECTURE.md) for the window-tracking and overlay design. In short:

- **Window tracking**: the Core Graphics window list gives stable window numbers, frames and stacking order. Accessibility observers say *when* to look (created / moved / resized / minimized / focus / app hidden). While you drag or resize, the list is polled at display rate; otherwise a 0.6 s reconciliation catches anything missed. Each window is classified once via its AX role/subrole so dialogs, panels, popovers and system UI are skipped.
- **Overlays**: one transparent, borderless, non-activating, click-through window per display (`ignoresMouseEvents = true`), joined to all Spaces, with a SpriteKit scene. When nothing is happening the view drops to 20–30 fps, and when there are no sites it pauses entirely.
- **Simulation**: a procedural scaffold generator lays out deck bays, tower levels, ladders, crane and pulley in art pixels from the window's size and the screen bounds; workers are step-queue state machines with personality-weighted idle choices; a director runs the construction, teardown and pack/rebuild choreography; small springs and pendulums handle props and hanging loads.

## Privacy

No servers, accounts, analytics or network requests. Lilliput keeps only each window's number, owning process, bundle identifier and frame, in memory, while the window exists. Settings are stored in the app's local defaults.

## Status

See [ARCHITECTURE.md → Implementation status](ARCHITECTURE.md#implementation-status) for what is fully implemented, what is limited, and how it was verified.
