# TFTOverlay

A native macOS starter app for a transparent, click-through TFT overlay.

## What works now

- Creates a borderless transparent overlay window above other apps.
- Keeps mouse clicks passing through to the game below.
- Opens a normal selectable settings window for controlling the overlay.
- Shows a small status panel and temporary stage hints.
- Polls Riot's local League Client API via the `lockfile`.
- Polls Riot's local Live Client Data API at `https://127.0.0.1:2999/liveclientdata/allgamedata`.
- Runs a native Apple Vision OCR probe over known TFT UI regions.
- Matches detected augment choice titles to the local TFT Academy tier cache.
- Writes a timestamped NDJSON capture file for offline development.

Run it with:

```sh
make run
```

Use the settings window or the menu bar item named `TFT` to toggle the overlay, open logs, or quit.

The built app bundle is written to `.build/TFTOverlay.app`.

## Collection Logs

Every launch creates a capture file at:

```text
~/Library/Application Support/TFTOverlay/Captures/collection-YYYY-MM-DD_HH-mm-ss.ndjson
```

Each line is a standalone JSON record. The first line is `session_start`; each later `poll` record includes:

- parsed overlay state, phase, game time, and stage hint
- raw `/liveclientdata/allgamedata` status/body/error
- a summary of live game keys, players, events, and game data
- sanitized lockfile metadata without the password
- raw League Client endpoint status/body/error for:
  - `/lol-gameflow/v1/gameflow-phase`
  - `/lol-gameflow/v1/session`
  - `/lol-lobby/v2/lobby`
  - `/lol-lobby/v2/lobby/members`
  - `/lol-matchmaking/v1/search`
  - `/lol-summoner/v1/current-summoner`
  - `/lol-login/v1/session`
- a `visionProbe` section with OCR text/candidates/confidence for round, gold, shop names, and augment title regions
- parsed `augmentTierOverlays` with matched augment name, TFT Academy tier, stage, and match score
- periodic crop PNGs in `~/Library/Application Support/TFTOverlay/Captures/VisionCrops`

The Vision probe may require macOS Screen Recording permission for `TFTOverlay`. It is intentionally a data collection layer first: expect some misses until the crop coordinates and recognition rules are tuned against real screenshots. macOS ties this permission to the app's code identity; for a stable development loop, sign the app with a persistent local or Apple development certificate. Check available identities with `make signing-identities`, then run with `make run CODESIGN_IDENTITY="Apple Development: Your Name (...)"`. Without a signing identity, `make run` launches the app executable directly, which is usually less noisy during development than `open`ing the rebuilt app bundle. Use `make run-open` for the old app-bundle launch behavior.

Open the capture folder from the menu bar item or with:

```sh
make logs
```

During a collection run, `Cmd-N` starts or saves a calibration box, and `Cmd-S` saves a full manual League/window snapshot into `ManualSnapshots/` with an `@@TFT_OVERLAY_MANUAL_SNAPSHOT@@` log entry.

Render the overlay onto the newest saved manual snapshot for out-of-game testing with:

```sh
make offline-preview
```

Analyze the largest capture with:

```sh
make analyze-logs
```

From the first full-game capture, Riot's local JSON exposed game phase, game timer, generic events, player shells, gold, and level, but not TFT board, bench, shop, exact round, or offered augment choices. Those will need a screen-recognition layer.

## TFT Academy Data

Scrape TFT Academy tier data with:

```sh
make scrape
```

This writes `data/tftacademy/latest.json` plus a timestamped snapshot. It currently fetches:

- comps from `https://tftacademy.com/tierlist/comps`
- augments from `https://tftacademy.com/api/tierlist/augments?set=17`
- items from `https://tftacademy.com/api/tierlist/items?set=17`

The augment index is keyed by Riot API name, stage, augment tier, and TFT Academy tier, so once offered augment recognition exists the overlay can show the tier under each offered augment.

The scraper also enriches augment rows with display names from CommunityDragon static TFT data. Run `make scrape` before `make run` when the set or patch changes so the bundled app cache is fresh.

## Game state approach

The app only reads local Riot API surfaces right now. That is the right first layer because it avoids process memory reads, packet inspection, game automation, or input injection.

For TFT-specific details that Riot does not expose in local JSON, such as exact augment selection UI, board state, bench, shop, or items, the likely next approved-friendly approach is screen OCR/computer vision with macOS Screen Recording permission. That can detect visible UI state without touching the game process.

The current Vision probe follows the same broad shape as older OCR bots: locate the League game window, scale known 1920x1080 TFT regions to the actual window size, OCR those crops, then match results against known TFT data. Unlike older Windows/Tesseract bots, this app uses Apple's native Vision framework and only logs observations for now.

## macOS notes

The overlay is most reliable when League/TFT is in windowed or borderless mode. True fullscreen Spaces are stricter on macOS, though the window uses `fullScreenAuxiliary` and `screenSaver` level to maximize compatibility.

## Riot policy notes

Keep this app informational:

- Do not automate gameplay.
- Do not send clicks or keystrokes to the game.
- Do not read or modify game memory.
- Do not expose hidden/opponent information Riot intentionally withholds.
- Do not include a Riot API key in a distributed binary.

## License

TFTOverlay is source-available under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate license from the copyright holder.
