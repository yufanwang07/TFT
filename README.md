# TFTOverlay

A native macOS starter app for a transparent, click-through TFT overlay.

## What works now

- Creates a borderless transparent overlay window above other apps.
- Keeps mouse clicks passing through to the game below.
- Opens a normal selectable settings window for controlling the overlay.
- Shows a small status panel and temporary stage hints.
- Polls Riot's local League Client API via the `lockfile`.
- Polls Riot's local Live Client Data API at `https://127.0.0.1:2999/liveclientdata/allgamedata`.
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

Open the capture folder from the menu bar item or with:

```sh
make logs
```

## Game state approach

The app only reads local Riot API surfaces right now. That is the right first layer because it avoids process memory reads, packet inspection, game automation, or input injection.

For TFT-specific details that Riot does not expose in local JSON, such as exact augment selection UI, board state, bench, shop, or items, the likely next approved-friendly approach is screen OCR/computer vision with macOS Screen Recording permission. That can detect visible UI state without touching the game process.

## macOS notes

The overlay is most reliable when League/TFT is in windowed or borderless mode. True fullscreen Spaces are stricter on macOS, though the window uses `fullScreenAuxiliary` and `screenSaver` level to maximize compatibility.

## Riot policy notes

Keep this app informational:

- Do not automate gameplay.
- Do not send clicks or keystrokes to the game.
- Do not read or modify game memory.
- Do not expose hidden/opponent information Riot intentionally withholds.
- Do not include a Riot API key in a distributed binary.
