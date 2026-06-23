# macOS State Source Research

This branch tracks whether TFTOverlay can replace slow OCR with a faster non-visual state source on macOS.

## Short answer

Windows overlays can receive richer game state through sanctioned platform/provider APIs such as Overwolf. That does not automatically translate to macOS process-memory access. On macOS, reading another app's internal memory through Mach APIs is technically possible only when the OS grants a task port for that process, but it is not a practical distribution path for this overlay.

The recommended direction is:

1. Prefer Riot/local HTTP APIs wherever they expose enough data.
2. Probe additional local League Client endpoints in a read-only way.
3. Keep Apple Vision/screen recognition for TFT-only state that is visibly present but not exposed by API.
4. Add a pluggable `GameStateSource` boundary so a sanctioned fast source can be dropped in later.
5. Do not ship raw game-memory scanning unless Riot explicitly provides/approves that mechanism for macOS.

## What Riot exposes locally

Riot documents the Live Client Data API at `https://127.0.0.1:2999/liveclientdata`. The useful endpoint for discovery is:

```text
GET https://127.0.0.1:2999/liveclientdata/allgamedata
```

The documented payload is built around active player data, player lists, items, events, and game stats. In our capture logs, this gave generic game/player shell data, but not TFT board slots, bench, shop, augment offers, or god choices.

The League Client API exposed through the lockfile is still worth probing. It may have TFT-specific lobby/session/progression endpoints, and we can inspect the client swagger/openapi surface read-only. That is a safer path than memory inspection because it stays in local HTTPS APIs the client already publishes.

## Accessibility API

macOS Accessibility can inspect accessibility elements, window titles, positions, buttons, and text exposed by an app's UI tree after the user grants permission. It is useful for:

- finding/selecting the League game window,
- getting app/window names and geometry,
- interacting with normal Cocoa controls in our own app.

It is not a way to read TFT internal gameplay objects. The game scene is rendered, so champions, board state, shop cards, and augment cards are pixels rather than AX text elements. Accessibility can improve window targeting, but it will not replace OCR for rendered game content.

## Mach / kernel memory access

The relevant macOS family of APIs is `task_for_pid`, `mach_vm_region`, and `mach_vm_read_overwrite`.

In principle, the flow is:

```text
pid of League game process
-> task_for_pid(mach_task_self(), pid, &task)
-> enumerate VM regions
-> read bytes with mach_vm_read_overwrite
-> reverse engineer structures/pointers/offsets
```

The blockers are substantial:

- A normal app does not get another production app's task port just because the user gave Screen Recording or Accessibility permission.
- Access is constrained by signing, entitlements, authorization, sandboxing, System Integrity Protection, hardened runtime, and process protections.
- Root/debug setups can change the result on a developer machine but are not a shippable user experience.
- Offsets and structures would be patch-sensitive and would require continuous reverse engineering.
- It risks reading information that is not visibly available to the player, which is exactly the boundary Riot's game-integrity policy calls out.

So Mach memory reading is a lab/debug research path, not a product path for this app.

## Overwolf comparison

Overwolf-style overlays are materially different from raw memory scanning. They run inside a platform that supplies game events and approved APIs. The app consumes the platform's normalized state rather than opening the game process and reverse engineering object memory itself.

For macOS, the equivalent target should be a sanctioned provider API or a local endpoint, not direct Mach reads. If Riot or another approved provider exposes TFT events on macOS, we should integrate through that source behind the same `GameStateSource` interface.

## Proposed app architecture

Add a single normalized state object fed by multiple sources:

```text
RiotLiveClientSource       fast, official, generic
LeagueClientSource         fast, local lockfile API, read-only endpoint probing
VisionStateSource          slower, visible TFT UI only
FutureSanctionedSource     Overwolf-like/event/provider API if available
MemoryStateSource          disabled research stub only
```

Each source should report:

- `freshnessMs`
- `confidence`
- `sourceName`
- specific fields it owns
- profiling timing

The overlay should merge fields by trust and freshness. For example, if API phase/game time is available, never OCR it; if augment color gates say no augment UI, skip augment OCR; if trait OCR fails, retain last valid board reconstruction for display stability.

## Safe next experiments

1. Add an LCU endpoint discovery command that fetches the League Client swagger/openapi spec through the lockfile and prints endpoint names containing `tft`, `teamfight`, `augment`, `inventory`, `bench`, `shop`, `board`, `unit`, or `companion`.
2. Log all currently available Live Client Data keys in game and compare TFT vs Summoner's Rift payloads.
3. Add a `GameStateSource` abstraction in code so OCR results are just one provider.
4. Keep Mach memory work as documentation-only unless a sanctioned macOS API appears.

## Sources

- Riot Developer Portal, Live Client Data API: https://developer.riotgames.com/docs/lol#game-client-api_live-client-data-api
- Riot Developer Portal, Game Integrity policy: https://developer.riotgames.com/docs/lol#developer-api-policy_game-integrity
- Apple Developer Documentation, AXUIElement / Accessibility API: https://developer.apple.com/documentation/applicationservices/axuielement
- Apple Developer Documentation, ScreenCapture access checks: https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29
- Apple Developer Documentation, System Integrity Protection: https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection
