# Sisyphus

![Sisyphus pushing his boulder up the hill, the rock rolling back down, and him following it and sitting](docs/sisyphus.gif)

[![Release](https://github.com/zaterka/sisyphus/actions/workflows/release.yml/badge.svg)](https://github.com/zaterka/sisyphus/actions/workflows/release.yml)

A task manager for a never-ending workflow.

## [⬇︎ Download for Mac](https://github.com/zaterka/sisyphus/releases/latest/download/Sisyphus.dmg)

Universal build for macOS 14 or later — Apple Silicon and Intel. Always the newest version.

Sisyphus is a small, native macOS task manager. It lives in a borderless panel that floats above
your other windows, pinned to the top-right corner of the screen, and shows a SNES-style pixel-art
Sisyphus pushing his boulder up a hill. The more tasks you finish, the higher he gets. When the
last one is done, the rock rolls back down, he follows it and sits until you add more.

## Install

You do not need a developer account, Homebrew or Terminal for this. It takes a minute.

1. **Download** [Sisyphus.dmg](https://github.com/zaterka/sisyphus/releases/latest/download/Sisyphus.dmg)
   and open the downloaded file.
2. **Drag Sisyphus** onto the Applications folder shown in the window, then eject the disk image.
3. **Open Sisyphus** from your Applications folder. macOS will block the first launch, because the
   app is not notarised by Apple — it says it cannot verify the developer. Close that dialog, but do
   **not** click **Move to Trash** / **Move to Bin**: that would delete the app. Then open
   **System Settings › Privacy & Security**, scroll down to the message about Sisyphus and click
   **Open Anyway**, and confirm. This is needed only once; after that Sisyphus opens normally.
   (The **Open Anyway** button only appears after one blocked launch attempt, so try to open the app
   first.)
4. If macOS instead says the app **is damaged**, that is the download quarantine flag. Open
   **Terminal** (Applications › Utilities) and paste this line, then press Return:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Sisyphus.app
   ```

   Then open Sisyphus again.

Do not turn Gatekeeper off. The app is unsigned only because a paid Apple Developer account is not
worth it for a single-purpose utility; the steps above are the safe and intended way past it. Your
tasks never leave your Mac — see [Data](#data).

## Requirements

- To use the app: macOS 14 or later, on Apple Silicon or Intel.
- To build it: the Xcode Command Line Tools (Swift 6 toolchain). Full Xcode is not required.

## Build and run

```sh
./scripts/build-app.sh      # builds a release binary and assembles build/Sisyphus.app
open build/Sisyphus.app
```

The script signs the bundle ad-hoc so macOS will launch it locally. It keeps SwiftPM's caches
inside the repository (`.build/`, `.spm-*/`, `.modcache/`) instead of `~/Library`.

## Test

```sh
./scripts/test.sh
```

The tests use Swift Testing and cover the pure `SisyphusCore` module: the task list, progress and
summit rules, reordering, sanitisation, persistence and the scene state machine. The script picks
the right flags for the installed toolchain: with the Command Line Tools it points the compiler at
the Swift Testing framework they ship (and works around a broken framework overlay), and with full
Xcode it just runs `swift test`.

## Development

```sh
./scripts/make-gif.sh       # renders docs/sisyphus.gif from the real scene code
./scripts/make-dmg.sh       # packages build/Sisyphus.app and an Applications link into build/Sisyphus.dmg
```

`build-app.sh` takes two environment variables:

```sh
UNIVERSAL=1 APP_VERSION=1.0.7 BUILD_NUMBER=7 ./scripts/build-app.sh
```

`UNIVERSAL=1` builds `arm64` and `x86_64` as two single-arch passes (`--triple`) and merges both
slices with `lipo`, asserting that the result really has both. `APP_VERSION` and `BUILD_NUMBER` set
`CFBundleShortVersionString` and `CFBundleVersion` on the assembled bundle — before signing, so the
signature covers them; the checked-in `Resources/Info.plist` is never modified.

The GIF is not hand-made. `--export-gif <path>` is a hidden CLI mode of the app binary: it drives
the real `SceneStateMachine` with a real `TaskList` value — four tasks completed one at a time, so
`progress`, `summitPending` and `hasOpenTasks` are exactly what the app computes — and draws every
frame through `SceneRenderer` at 640×360, 20 fps. The scenario is deterministic (a fixed clock,
frames counted rather than timed), so `make-gif.sh` reproduces the same animation, and it exits
non-zero if the scene fails to climb, reach the summit, roll, walk down and settle into the sit.

### Releases

`.github/workflows/release.yml` runs on every push to `main` and on demand: it tests, builds a
universal `Sisyphus.app`, packages the DMG and publishes it to one rolling release tagged `latest`.
Pull requests build and test only and never publish — and so does a manual run dispatched from any
branch other than `main`. Documentation-only changes are skipped.

The workflow force-moves the `latest` tag to the built commit, then either creates the release (on
the very first run) or replaces the DMG asset in place with `gh release upload --clobber`. That keeps
`.../releases/latest/download/Sisyphus.dmg` alive at all times, so there is no window where the
download link 404s.

This needs **immutable releases to be off**. Check **Settings › General › Releases** and make sure it
is disabled: with immutable releases on, both the force-move of the `latest` tag and the asset upload
are rejected, so the workflow fails at the publish step and the download never updates. GitHub ships
the setting off, but treat that as something to verify rather than something to rely on — if a
publish starts failing with a release-related error, look there first.

## Features

- **Floating panel.** Borderless, always on top, visible on every Space, with a Dock icon. On
  launch it sits at the top-right of the main screen, 12 pt from the edges, and re-pins itself
  when the screen layout changes — unless you dragged it somewhere else using the grip in the
  toolbar.
- **Tasks.** Type in the add field and press Return. A `#word` anywhere in the text becomes the
  task's tag (`buy milk #home`). Each task has a title, a priority (none / low / medium / high,
  shown as a blue / orange / red dot), one tag, and an optional due date shown as "Today",
  "Tomorrow" or a short date.
- **Editing.** Click the pencil, double-click the row, or use the context menu to open the editor
  popover. Changes are applied when it closes. It also has a Delete button.
- **Reorder.** Drag open tasks to change their order.
- **Completed.** Ticking a task moves it to the collapsible "Completed (n)" section, where rows
  are struck through and dimmed. Tick it again to reopen it. Use the context menu to delete it,
  or "Clear completed" to remove them all.
- **Scene only.** The toolbar toggle (or ⌘T) hides the task list and leaves only the scene. The
  panel shrinks or grows with its top edge fixed, and the setting is remembered.

### Keyboard

These are ordinary menu shortcuts, so they work only while Sisyphus is the active app:

| Shortcut | Action |
|---|---|
| ⌘N | New task: shows the list if hidden and focuses the add field |
| ⌘T | Toggle the task list |
| ⌘H | Hide |
| ⌘Q | Quit |

The standard Edit shortcuts (⌘Z, ⇧⌘Z, ⌘X, ⌘C, ⌘V, ⌘A) work in the text fields.

### Focus trade-off

Clicking the panel activates Sisyphus, which takes focus from the app you were using. Without
this, the panel's text fields could not receive typing.

## How the mechanic works

Progress is

```
completedSinceReset / (completedSinceReset + open tasks)
```

`completedSinceReset` counts the tasks finished since the last time he reached the summit.

- **Adding** a task increases the denominator, so he slides back down a little.
- **Completing** a task increases the counter, so he climbs.
- **Reopening** a task undoes one completion.
- **Deleting** or clearing completed tasks does not take progress away.

He moves toward the target at a capped speed, so quick changes look like smooth pushing, not
jumps.

When no open tasks are left and at least one was completed, he reaches the **summit**:

1. He holds at the top for a moment.
2. The rock rolls all the way down and bounces.
3. He walks down after it and sits next to it.

The counter is then reset to zero. The sequence always plays to the end, and takes about 4.6
seconds. If you add a task while it is playing, he finishes the sequence, then stands up and
starts pushing again from the bottom.

Deleting the last open task also triggers the summit if you had completed something, because
there is nothing left to push. If you quit during the summit, it replays on the next launch.

With nothing left to push and nothing to be earned, he just walks back down to the boulder and
sits — no summit, no rolling rock. While he sits the scene runs at a reduced rate, so an idle
Sisyphus costs almost nothing.

## Data

Tasks are stored as JSON in `~/Library/Application Support/Sisyphus/tasks.json`.

- Saving waits 0.3 s after the last change, writes atomically, and also happens on quit.
- If the file cannot be decoded, it is renamed to `tasks.corrupt-<timestamp>.json` and the app
  starts empty instead of failing.
- The file location is logged at launch under the subsystem `com.sisyphus.app`.

## Layout

```
Sources/SisyphusCore/         pure, testable logic (Foundation and os): tasks, persistence, scene state machine
Sources/Sisyphus/             the app: AppKit panel and menu, SwiftUI views, the scene (Scene/)
Sources/Sisyphus/Scene/       sprites, background, renderer, layout, and the hidden --export-gif mode
Tests/SisyphusCoreTests/      Swift Testing tests for SisyphusCore
Resources/Info.plist          bundle metadata used by build-app.sh
scripts/                      build-app.sh, test.sh, make-gif.sh, make-dmg.sh
docs/sisyphus.gif             the animation above, rendered from the scene code
.github/workflows/release.yml CI: test, universal build, DMG, rolling `latest` release
```
