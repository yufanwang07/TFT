#!/usr/bin/env python3

import collections
import glob
import json
import os
import sys


CAPTURE_DIR = os.path.expanduser("~/Library/Application Support/TFTOverlay/Captures")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else largest_capture()
    polls = []
    for record in read_records(path):
        if record.get("type") == "poll":
            polls.append(record)

    phase_counts = collections.Counter(p.get("parsed", {}).get("phase") for p in polls)
    live_polls = [p for p in polls if isinstance(p.get("parsed", {}).get("gameTime"), (int, float))]
    event_timeline = collect_event_timeline(live_polls)

    print(f"Capture: {path}")
    print(f"Poll records: {len(polls)}")
    print(f"Live game records: {len(live_polls)}")
    print(f"Phases: {dict(phase_counts)}")
    if live_polls:
        first = live_polls[0]
        last = live_polls[-1]
        print(f"Game time: {first['parsed']['gameTime']:.1f}s -> {last['parsed']['gameTime']:.1f}s")

    print("\nLive Client Data shape:")
    print_live_shape(live_polls)

    print("\nUnique live events:")
    for event in event_timeline:
        print(f"- {event.get('EventTime', 0):7.1f}s {event.get('EventName')} {event_summary(event)}")

    print("\nVision probe:")
    print_vision_probe(polls)

    print("\nAugment detection note:")
    print("- The captured Riot live data does not expose augment choice options or TFT round state.")
    print("- Previous hints were based only on absolute gameTime and should not be used.")
    print("- Board, bench, shop, and offered augments were not present in LCU/live JSON; use screen capture/OCR for those.")


def largest_capture():
    paths = glob.glob(os.path.join(CAPTURE_DIR, "*.ndjson"))
    if not paths:
        raise SystemExit(f"No captures found in {CAPTURE_DIR}")
    return max(paths, key=os.path.getsize)


def read_records(path):
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                yield json.loads(line)


def collect_event_timeline(polls):
    seen = {}
    for poll in polls:
        body = poll.get("liveAllGameData", {}).get("body") or ""
        if not body:
            continue
        try:
            live = json.loads(body)
        except json.JSONDecodeError:
            continue
        for event in live.get("events", {}).get("Events", []):
            key = (
                event.get("EventID"),
                event.get("EventName"),
                event.get("EventTime"),
                event.get("KillerName"),
                event.get("VictimName"),
            )
            seen[key] = event
    return sorted(seen.values(), key=lambda e: (e.get("EventTime", 0), e.get("EventID", 0)))


def print_live_shape(polls):
    good = None
    for poll in polls:
        body = poll.get("liveAllGameData", {}).get("body") or ""
        try:
            candidate = json.loads(body)
        except json.JSONDecodeError:
            continue
        if "gameData" in candidate:
            good = candidate
            break

    if not good:
        print("- No successful live data payload found.")
        return

    active = good.get("activePlayer", {})
    players = good.get("allPlayers", [])
    game_data = good.get("gameData", {})
    print(f"- gameData: {game_data}")
    print(f"- activePlayer keys: {sorted(active.keys())}")
    print(f"- allPlayers count: {len(players)}")
    if players:
        print(f"- allPlayers[0] keys: {sorted(players[0].keys())}")
    print("- No board, bench, shop, augment-option, or round-number keys were found.")


def event_summary(event):
    parts = []
    for key in ("KillerName", "VictimName"):
        if event.get(key):
            parts.append(f"{key}={event[key]}")
    return " ".join(parts)


def print_vision_probe(polls):
    probes = [p.get("visionProbe", {}) for p in polls if p.get("visionProbe")]
    if not probes:
        print("- No visionProbe records found.")
        return

    available = sum(1 for probe in probes if probe.get("available"))
    print(f"- probe records: {len(probes)}, available captures: {available}")

    errors = collections.Counter(
        probe.get("error") for probe in probes if probe.get("error")
    )
    if errors:
        print(f"- errors: {dict(errors)}")

    by_region = collections.defaultdict(list)
    crop_paths = []
    for probe in probes:
        for region in probe.get("regions", []):
            by_region[region.get("id", "unknown")].append(region)
            if region.get("imagePath"):
                crop_paths.append(region["imagePath"])

    for region_id in sorted(by_region):
        observations = by_region[region_id]
        non_empty = [obs for obs in observations if obs.get("text")]
        sample = non_empty[:3] if non_empty else observations[:1]
        print(f"- {region_id}: {len(non_empty)}/{len(observations)} non-empty")
        for obs in sample:
            confidence = 0
            candidates = obs.get("candidates") or []
            if candidates:
                confidence = candidates[0].get("confidence", 0)
            print(f"  text={obs.get('text', '')!r} confidence={confidence:.2f}")

    if crop_paths:
        print("- saved crop examples:")
        for path in crop_paths[:5]:
            print(f"  {path}")


if __name__ == "__main__":
    main()
