# Development

How Sisyphus is built, tested and released; the [README](../README.md) covers what the app does.

Every command and file path below is relative to the repository root — that is where you run them.
The markdown links are relative to this file, so they start with `../`.

## Build requirements

- macOS 14 or later, on Apple Silicon or Intel.
- The Xcode Command Line Tools (Swift 6 toolchain). Full Xcode is not required.

The deployment target comes from the bundle metadata: [Package.swift](../Package.swift) declares
macOS 14, and the build script reads `LSMinimumSystemVersion` straight out of
[Resources/Info.plist](../Resources/Info.plist), so the two cannot drift apart.

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
./scripts/make-logo.sh      # renders docs/logo.png and Resources/AppIcon.icns from LogoArt.swift
./scripts/make-dmg.sh       # packages build/Sisyphus.app, LICENSE and an Applications link into build/Sisyphus.dmg
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

The logo is generated from code as well. `./scripts/make-logo.sh` renders it from
`Sources/Sisyphus/Scene/LogoArt.swift` through the binary's hidden `--export-logo <dir>` mode, then
writes `docs/logo.png` (512×512, the README header image) and `Resources/AppIcon.icns`, assembled
with `iconutil` from the exported `AppIcon.iconset` and shipped inside the app bundle. Both outputs
are committed. CI never runs `make-logo.sh`; it ships the committed `.icns`. So after editing
`LogoArt.swift`, re-run the script and commit both outputs, or the release keeps the old icon.

The script asserts the pixel size of every PNG with `sips` and round-trips the `.icns` back through
`iconutil -c iconset` before copying the results into place, so a broken export fails there instead
of on a user's Mac.

The logo master grid is 64×64 logical pixels, drawn inside a staircase rounded square (a six-cell
inset, transparent outside), so the 64 to 1024 px reps are all exact integer scales of it. The
16 px and 32 px icon reps come from a separate, hand-authored simplified 16×16 grid. No art is ever
decimated or interpolated: every rep is an exact integer nearest-neighbour scale.

Documentation-only changes are skipped by the release workflow: `**.md` and `docs/**` are in its
`paths-ignore`, so regenerating `docs/logo.png` alone does not republish the DMG, while a new
`Resources/AppIcon.icns` does, because it lives outside `docs/`.

The two hidden export modes are read by [main.swift](../Sources/Sisyphus/main.swift), which accepts
at most one of them per run: `--export-gif` and `--export-logo` together are a usage error.

`make-dmg.sh` writes the image twice. It first creates a read-write `HFS+` image of the staging
folder and mounts it, which is the only way to give a DMG a volume icon: `AppIcon.icns` is copied
to `.VolumeIcon.icns` at the volume root and tagged with `SetFile`, because the icon lives in the
volume's catalog attributes rather than in a resource fork. It then detaches that image and runs
`hdiutil convert -format UDZO` for the compressed file that ships. The result is verified by
mounting it read-only and asserting that the app binary, the `Applications` link, `Install.txt` and
`LICENSE` are present — plus the volume's custom-icon attribute, when `SetFile` was available to set
it. Without `SetFile` a developer machine gets a warning and a plain volume; with `CI` set the build
fails instead, so a release can never quietly ship an icon-less image.

## Releases

[.github/workflows/release.yml](../.github/workflows/release.yml) runs on every push to `main` and
on demand: it tests, builds a universal `Sisyphus.app`, packages the DMG and publishes it to one
rolling release tagged `latest`. Pull requests build and test only and never publish — and so does
a manual run dispatched from any branch other than `main`. Documentation-only changes are skipped,
because `**.md` and `docs/**` are in the workflow's `paths-ignore`.

`LICENSE` is not covered by that `paths-ignore`, so changing it triggers a rebuild and republishes
the DMG. That is intended.

The workflow force-moves the `latest` tag to the built commit, then either creates the release (on
the very first run) or replaces the DMG asset in place with `gh release upload --clobber`. That keeps
`.../releases/latest/download/Sisyphus.dmg` alive at all times, so there is no window where the
download link 404s.

This needs **immutable releases to be off**. Check **Settings › General › Releases** and make sure it
is disabled: with immutable releases on, both the force-move of the `latest` tag and the asset upload
are rejected, so the workflow fails at the publish step and the download never updates. GitHub ships
the setting off, but treat that as something to verify rather than something to rely on — if a
publish starts failing with a release-related error, look there first.

## Layout

```
Sources/SisyphusCore/         pure, testable logic (Foundation and os): tasks, persistence, scene state machine
Sources/Sisyphus/             the app: AppKit panel and menu, SwiftUI views, the scene (Scene/)
Sources/Sisyphus/Scene/       sprites, background, renderer, layout, and the hidden export modes
Sources/Sisyphus/Scene/LogoArt.swift        the 64x64 and simplified 16x16 logo pixel grids and palette
Sources/Sisyphus/Scene/LogoExporter.swift   the hidden --export-logo mode: logo.png and AppIcon.iconset
Tests/SisyphusCoreTests/      Swift Testing tests for SisyphusCore
Resources/Info.plist          bundle metadata used by build-app.sh
Resources/AppIcon.icns        the app icon, generated by scripts/make-logo.sh
scripts/                      build-app.sh, test.sh, make-gif.sh, make-logo.sh, make-dmg.sh
LICENSE                       verbatim GPL-3.0 text, shipped in the app bundle and the DMG
docs/logo.png                 the README header logo (512x512)
docs/sisyphus.gif             the animated demo, rendered from the scene code
docs/DEVELOPMENT.md           this file
.github/workflows/release.yml CI: test, universal build, DMG, rolling `latest` release
```
