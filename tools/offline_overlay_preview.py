#!/usr/bin/env python3

import argparse
import datetime as dt
import glob
import json
import math
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


CAPTURE_DIR = Path.home() / "Library/Application Support/TFTOverlay/Captures"
DATA_DIR = Path("data/tftacademy")

TIER_COLORS = {
    "X": ((5, 97, 122), (13, 209, 245)),
    "S": ((122, 10, 20), (255, 20, 41)),
    "A": ((178, 77, 10), (255, 122, 26)),
    "B": ((184, 143, 20), (255, 199, 26)),
    "C": ((13, 107, 56), (20, 184, 92)),
}

COST_COLORS = {
    1: (158, 168, 178),
    2: (20, 199, 92),
    3: (20, 153, 255),
    4: (168, 77, 255),
    5: (255, 191, 15),
}

CARD_ZONES = [(350, 276, 700, 836), (785, 276, 1135, 836), (1220, 276, 1570, 836)]
TIER_CENTERS = [522, 960, 1392]
HERO_AUGMENTS = {
    "selfdestruct",
    "thebigbang",
    "invaderzed",
    "shieldmaiden",
    "stellarcombo",
    "reachforthestars",
    "heatdeath",
    "termeepnalvelocity",
    "terminalvelocity",
    "bonk",
    "contractkiller",
}


def main():
    parser = argparse.ArgumentParser(description="Render TFT overlay output onto a saved screenshot/manual snapshot.")
    parser.add_argument("image", nargs="?", help="Screenshot/manual snapshot PNG. Defaults to newest manual snapshot.")
    parser.add_argument("--log", help="NDJSON collection log. Defaults to the log containing the snapshot, or newest log.")
    parser.add_argument("--out", help="Output PNG path.")
    parser.add_argument("--show-regions", action="store_true", help="Draw OCR/click regions even when no augment matches exist.")
    parser.add_argument("--hover", help="Render comp hover tooltip as slot:index, using 1-based numbers. Example: 1:1")
    args = parser.parse_args()

    image_path = Path(args.image).expanduser() if args.image else newest_manual_snapshot()
    log_path = Path(args.log).expanduser() if args.log else find_log_for_image(image_path)
    output_path = Path(args.out).expanduser() if args.out else Path("offline-previews") / f"{image_path.stem}-overlay-preview.png"

    records = read_records(log_path)
    manual_record = find_manual_record(records, image_path)
    poll = nearest_poll(records, manual_record)
    matches = current_matches(poll)

    image = Image.open(image_path).convert("RGBA")
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    scale_x = image.width / 1920.0
    scale_y = image.height / 1080.0

    if args.show_regions or has_three_valid_matches(matches):
        draw_click_debug_borders(draw, scale_x, scale_y)

    hover = parse_hover(args.hover)
    hovered_badge = None
    hovered_rect = None
    for match in matches:
        result = draw_match(overlay, draw, match, scale_x, scale_y, hover)
        if result:
            hovered_badge, hovered_rect = result

    if hovered_badge and hovered_rect:
        draw_comp_tooltip(overlay, draw, hovered_badge, hovered_rect, min(scale_x, scale_y), image.size)

    draw_debug_panel(draw, poll, matches, image.size)
    rendered = Image.alpha_composite(image, overlay)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    rendered.save(output_path)

    print(f"Image: {image_path}")
    print(f"Log: {log_path}")
    if manual_record:
        print(f"Manual snapshot timestamp: {manual_record.get('timestamp')}")
    if poll:
        print(f"Nearest poll timestamp: {poll.get('timestamp')}")
    print(f"Matches: {len(matches)}")
    for match in matches:
        print(f"- slot {int(match.get('slot', 0)) + 1}: {match.get('displayName')} => {match.get('tier')}")
    print(f"Rendered: {output_path}")


def parse_hover(value):
    if not value:
        return None
    try:
        slot, index = value.split(":", 1)
        return (int(slot) - 1, int(index) - 1)
    except Exception:
        raise SystemExit("--hover must be formatted as slot:index, for example 1:1")


def newest_manual_snapshot():
    paths = sorted(CAPTURE_DIR.glob("ManualSnapshots/*.png"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not paths:
        raise SystemExit(f"No manual snapshots found in {CAPTURE_DIR / 'ManualSnapshots'}")
    return paths[0]


def find_log_for_image(image_path):
    image_path = str(image_path)
    logs = sorted(CAPTURE_DIR.glob("collection-*.ndjson"), key=lambda p: p.stat().st_mtime, reverse=True)
    for log in logs:
        try:
            if image_path in log.read_text(encoding="utf-8"):
                return log
        except UnicodeDecodeError:
            continue
    if logs:
        return logs[0]
    raise SystemExit(f"No collection logs found in {CAPTURE_DIR}")


def read_records(path):
    records = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return records


def find_manual_record(records, image_path):
    target = str(image_path)
    for record in records:
        if record.get("type") == "MANUAL_SNAPSHOT" and record.get("imagePath") == target:
            return record
    sidecar = image_path.with_suffix(".json")
    if sidecar.exists():
        try:
            return json.loads(sidecar.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return None
    return None


def nearest_poll(records, manual_record):
    polls = [record for record in records if record.get("type") == "poll"]
    if not polls:
        return None
    if not manual_record or not manual_record.get("timestamp"):
        return polls[-1]
    target = parse_timestamp(manual_record["timestamp"])
    return min(polls, key=lambda poll: abs((parse_timestamp(poll.get("timestamp")) - target).total_seconds()))


def parse_timestamp(value):
    if not value:
        return dt.datetime.min.replace(tzinfo=dt.timezone.utc)
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def current_matches(poll):
    if not poll:
        return []
    matches = poll.get("parsed", {}).get("augmentTierOverlays") or []
    comp_badges = load_comp_badges_by_augment()
    normalized = []
    for match in matches:
        if not isinstance(match, dict):
            continue
        result = normalize_match(match)
        api_name = result.get("apiName")
        if api_name in comp_badges:
            result["compBadges"] = comp_badges[api_name]
        normalized.append(result)
    return normalized


def normalize_match(match):
    name = match.get("displayName", "")
    tier = match.get("tier", "")
    actual = match.get("actualTier", "")
    if normalized_name(name) in HERO_AUGMENTS:
        actual = tier
        tier = "X"
    result = dict(match)
    result["tier"] = tier
    result["actualTier"] = actual
    return result


def normalized_name(value):
    return "".join(ch for ch in str(value).lower() if ch.isalnum())


def load_comp_badges_by_augment():
    path = DATA_DIR / "latest.json"
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}

    champion_costs = {}
    for comp in data.get("comps") or []:
        main = comp.get("mainChampion") or {}
        if main.get("apiName") and main.get("cost"):
            champion_costs[main["apiName"]] = main["cost"]

    index = {}
    for comp in data.get("comps") or []:
        main = comp.get("mainChampion") or {}
        main_api = main.get("apiName") or ""
        badge = {
            "title": comp.get("title") or "Comp",
            "tier": comp.get("tier") or "",
            "style": comp.get("style") or "",
            "difficulty": comp.get("difficulty") or "",
            "championApiName": main_api,
            "mainChampion": main_api,
            "cost": main.get("cost"),
            "carousel": comp.get("carousel") or [],
            "traits": comp.get("traits") or [],
            "tips": comp.get("tips") or [],
            "finalComp": enrich_units_with_costs(comp.get("finalComp") or [], champion_costs),
        }
        api_names = set(comp.get("augments") or [])
        api_names.update(comp.get("overlayAugments") or [])
        main_augment = comp.get("mainAugment") or {}
        if main_augment.get("apiName"):
            api_names.add(main_augment["apiName"])
        for api_name in api_names:
            index.setdefault(api_name, []).append(badge)

    return {
        api_name: sorted(badges, key=lambda badge: (tier_rank(badge.get("tier")), badge.get("title") or ""))[:5]
        for api_name, badges in index.items()
    }


def enrich_units_with_costs(units, champion_costs):
    enriched = []
    for unit in units:
        if not isinstance(unit, dict):
            continue
        unit_copy = dict(unit)
        api_name = unit_copy.get("apiName")
        if "cost" not in unit_copy and api_name in champion_costs:
            unit_copy["cost"] = champion_costs[api_name]
        enriched.append(unit_copy)
    return enriched


def tier_rank(tier):
    return {"X": 0, "S": 0, "A": 1, "B": 2, "C": 3}.get(tier, 9)


def has_three_valid_matches(matches):
    slots = set()
    for match in matches:
        if match.get("displayName") and match.get("tier") and isinstance(match.get("slot"), int):
            if 0 <= match["slot"] < 3:
                slots.add(match["slot"])
    return len(slots) == 3


def draw_click_debug_borders(draw, scale_x, scale_y):
    for rect in CARD_ZONES:
        x1, y1, x2, y2 = scale_rect(rect, scale_x, scale_y)
        draw.rounded_rectangle((x1, y1, x2, y2), radius=12, outline=(77, 230, 255, 150), width=3)


def draw_match(overlay, draw, match, scale_x, scale_y, hover=None):
    slot = int(match.get("slot", -1))
    tier = match.get("tier") or ""
    if slot < 0 or slot >= 3 or not tier:
        return None

    center_x = TIER_CENTERS[slot] * scale_x
    tier_top_y = 740 * scale_y
    size = 66 * min(scale_x, scale_y)
    rect = (center_x - size / 2, tier_top_y, center_x + size / 2, tier_top_y + size)
    draw_tier_hex(draw, rect, tier, font_size=max(18, int(size * 0.43)))

    actual_tier = match.get("actualTier") or ""
    if tier == "X" and actual_tier and actual_tier != tier:
        small = size * 0.44
        top = ((rect[0] + rect[2]) / 2, rect[1] + 3)
        upper_left = (rect[0] + size * 0.25, rect[1] + size * 0.25)
        cx = (top[0] + upper_left[0]) / 2
        cy = (top[1] + upper_left[1]) / 2
        draw_tier_hex(draw, (cx - small / 2, cy - small / 2, cx + small / 2, cy + small / 2), actual_tier, font_size=max(9, int(small * 0.45)))

    return draw_comp_badges(overlay, draw, match.get("compBadges") or [], center_x, 808 * scale_y, min(scale_x, scale_y), slot, hover)


def draw_tier_hex(draw, rect, tier, font_size):
    outer, inner = TIER_COLORS.get(tier, ((38, 38, 38), (71, 71, 71)))
    outer_points = hex_points(rect)
    inner_rect = inset(rect, 6 * ((rect[2] - rect[0]) / 66.0))
    inner_points = hex_points(inner_rect)
    draw.polygon(outer_points, fill=highlight(outer, tier, 0.18) + (245,))
    draw.polygon(inner_points, fill=highlight(inner, tier, 0.16) + (245,))

    font = font_for_size(font_size)
    text = str(tier)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    cx = (rect[0] + rect[2]) / 2
    cy = (rect[1] + rect[3]) / 2 - (rect[3] - rect[1]) * 0.02
    draw.text((cx - tw / 2, cy - th / 2 - bbox[1]), text, font=font, fill=(0, 0, 0, 220))


def draw_comp_badges(overlay, draw, badges, center_x, top_y, scale, slot, hover=None):
    count = min(len(badges), 5)
    if count == 0:
        return None
    size = 30 * scale
    gap = 6 * scale
    total = count * size + (count - 1) * gap
    start_x = center_x - total / 2
    y = top_y
    hovered = None
    for index, badge in enumerate(badges[:count]):
        x = start_x + index * (size + gap)
        rect = (x, y, x + size, y + size)
        tier = badge.get("tier", "")
        cost_color = cost_color_for(badge.get("cost"))
        draw.ellipse(rect, fill=(0, 0, 0, 90), outline=cost_color + (230,), width=max(2, int(2.4 * scale)))
        icon = load_champion_icon(badge.get("championApiName"))
        if icon:
            icon = icon.resize((int(size), int(size)))
            mask = Image.new("L", icon.size, 0)
            ImageDraw.Draw(mask).ellipse((0, 0, icon.size[0] - 1, icon.size[1] - 1), fill=255)
            overlay.paste(icon.convert("RGBA"), (int(x), int(y)), mask)
            draw.ellipse(rect, outline=cost_color + (235,), width=max(2, int(2.4 * scale)))
        if hover == (slot, index):
            tier_color = TIER_COLORS.get(tier, ((80, 80, 80), (140, 140, 140)))[1]
            draw.ellipse(rect, fill=tier_color + (198,), outline=cost_color + (245,), width=max(2, int(2.4 * scale)))
            font = font_for_size(max(12, int(14 * scale)))
            draw_centered_text(draw, rect, tier, font, (0, 0, 0, 225))
            hovered = (badge, rect)
    return hovered


def load_champion_icon(api_name):
    return load_icon("champions", api_name)


def load_item_icon(api_name):
    return load_icon("items", api_name)


def load_trait_icon(api_name):
    return load_icon("traits", api_name)


def load_icon(subdirectory, api_name):
    if not api_name:
        return None
    for ext in ("webp", "png", "jpg", "jpeg"):
        path = DATA_DIR / subdirectory / f"{api_name}.{ext}"
        if path.exists():
            try:
                return Image.open(path)
            except Exception:
                return None
    return None


def draw_comp_tooltip(overlay, draw, badge, anchor_rect, scale, image_size):
    tips = badge.get("tips") or []
    traits = badge.get("traits") or []
    shown_tips = min(len(tips), 3)
    width = 700 * scale
    height = min((255 + (28 if traits else 0) + max(0, shown_tips - 2) * 22) * scale, 340 * scale)
    x = (anchor_rect[0] + anchor_rect[2]) / 2 - width / 2
    y = anchor_rect[1] - height - 18 * scale
    x = max(18 * scale, min(x, image_size[0] - width - 18 * scale))
    if y < 18 * scale:
        y = anchor_rect[3] + 18 * scale
    panel = (x, y, x + width, y + height)
    draw.rounded_rectangle(panel, radius=9 * scale, fill=(5, 5, 5, 230), outline=(255, 255, 255, 38), width=1)

    tier = badge.get("tier", "")
    tier_color = TIER_COLORS.get(tier, ((80, 80, 80), (150, 150, 150)))[1]
    sidebar_w = 190 * scale
    sidebar = (x + 1, y + 1, x + sidebar_w, y + height - 1)
    outer_color = TIER_COLORS.get(tier, ((42, 42, 42), (96, 96, 96)))[0]
    draw.rounded_rectangle(sidebar, radius=8 * scale, fill=outer_color + (210,))
    draw.rounded_rectangle(sidebar, radius=8 * scale, fill=(0, 0, 0, 62))

    icon_rect = (x + sidebar_w / 2 - 43 * scale, y + 26 * scale, x + sidebar_w / 2 + 43 * scale, y + 112 * scale)
    draw_hex_champion(overlay, draw, badge.get("championApiName"), icon_rect, tier_color, tier)
    title = str(badge.get("title") or "Comp").upper()
    style = str(badge.get("style") or "Playstyle TBD").upper()
    difficulty = str(badge.get("difficulty") or "").upper()
    meta = " | ".join(part for part in (style, difficulty) if part)
    draw_text_center(draw, title, (x + 14 * scale, y + 124 * scale, x + sidebar_w - 14 * scale, y + 152 * scale), font_for_size(int(17 * scale)), (255, 255, 255, 245))
    draw_text_center(draw, meta, (x + 12 * scale, y + 152 * scale, x + sidebar_w - 12 * scale, y + 172 * scale), font_for_size(int(11 * scale)), tier_color + (245,))
    draw_tier_pill(draw, tier, (x + sidebar_w / 2 - 42 * scale, y + 180 * scale, x + sidebar_w / 2 + 42 * scale, y + 204 * scale), scale)
    trait_height = 48 * scale if traits else 22 * scale
    draw_trait_list(overlay, draw, traits, (x + 14 * scale, y + height - 38 * scale - trait_height, x + sidebar_w - 14 * scale, y + height - 38 * scale), scale)
    cost = badge.get("cost")
    cost_label = f"{int(cost)}-cost carry" if isinstance(cost, int) else "Carry"
    draw_text_center(draw, cost_label, (x + 18 * scale, y + height - 30 * scale, x + sidebar_w - 18 * scale, y + height - 12 * scale), font_for_size(int(12 * scale)), (255, 255, 255, 194))

    content_x = x + sidebar_w + 20 * scale
    content_w = width - sidebar_w - 40 * scale
    draw_final_comp_row(overlay, draw, badge.get("finalComp") or [], (content_x, y + 18 * scale, content_x + content_w, y + 74 * scale), scale)
    draw_item_priority(overlay, draw, badge.get("carousel") or [], (content_x, y + 86 * scale, content_x + content_w, y + 146 * scale), scale)
    draw_notes(draw, tips, (content_x, y + 160 * scale, content_x + content_w, y + height - 18 * scale), scale)


def draw_final_comp_row(overlay, draw, units, rect, scale):
    draw.text((rect[0], rect[1]), "Final Comp", font=font_for_size(int(13 * scale)), fill=(255, 255, 255, 198))
    size = 38 * scale
    gap = 7 * scale
    y = rect[3] - size
    for index, unit in enumerate(units[:9]):
        api_name = unit.get("apiName") if isinstance(unit, dict) else ""
        cost = unit.get("cost") if isinstance(unit, dict) else None
        icon_rect = (rect[0] + index * (size + gap), y, rect[0] + index * (size + gap) + size, y + size)
        draw_hex_champion(overlay, draw, api_name, icon_rect, cost_color_for(cost), short_name(api_name))


def draw_item_priority(overlay, draw, items, rect, scale):
    draw.text((rect[0], rect[1]), "Item Priority", font=font_for_size(int(13 * scale)), fill=(255, 255, 255, 198))
    x = rect[0]
    y = rect[3] - 38 * scale
    size = 30 * scale
    for index, item in enumerate(items[:5]):
        api_name = item.get("apiName") if isinstance(item, dict) else str(item)
        icon_rect = (x, y, x + size, y + size)
        draw_rounded_item_icon(overlay, draw, api_name, icon_rect, compact_item_name(api_name), scale)
        x += size + 10 * scale
        if index + 1 < min(len(items), 5):
            draw_arrow(draw, (x - 3 * scale, y + 7 * scale, x + 5 * scale, y + 23 * scale), scale)
            x += 13 * scale


def draw_notes(draw, tips, rect, scale):
    draw.text((rect[0], rect[1]), "Tips", font=font_for_size(int(13 * scale)), fill=(255, 255, 255, 198))
    lines = []
    for tip in tips:
        if not isinstance(tip, dict):
            continue
        body = str(tip.get("tip") or "")
        if body:
            lines.append(body)
        if len(lines) >= 3:
            break
    text = "\n".join(lines) if lines else "No notes yet."
    font = font_for_size(int(10 * scale))
    y = rect[1] + 22 * scale
    max_chars = max(44, int((rect[2] - rect[0]) / (5.2 * scale)))
    for paragraph in text.splitlines():
        words = paragraph.split()
        line = ""
        for word in words:
            candidate = f"{line} {word}".strip()
            if len(candidate) > max_chars and line:
                draw.text((rect[0], y), line, font=font, fill=(255, 255, 255, 210))
                y += 14 * scale
                line = word
            else:
                line = candidate
        if line:
            draw.text((rect[0], y), line, font=font, fill=(255, 255, 255, 210))
            y += 14 * scale
        if y > rect[3] - 12 * scale:
            break


def draw_hex_champion(overlay, draw, api_name, rect, border_color, fallback):
    points = hex_points(rect)
    draw.polygon(points, fill=border_color + (245,))
    border = max(2, int((rect[2] - rect[0]) * 0.075))
    inner_rect = inset(rect, border)
    inner_points = hex_points(inner_rect)
    draw.polygon(inner_points, fill=(10, 10, 10, 238))
    icon = load_champion_icon(api_name)
    if icon:
        icon = icon.resize((max(1, int(inner_rect[2] - inner_rect[0])), max(1, int(inner_rect[3] - inner_rect[1]))))
        mask = Image.new("L", icon.size, 0)
        local_points = [(px - inner_rect[0], py - inner_rect[1]) for px, py in inner_points]
        ImageDraw.Draw(mask).polygon(local_points, fill=255)
        overlay.paste(icon.convert("RGBA"), (int(inner_rect[0]), int(inner_rect[1])), mask)
    else:
        draw_centered_text(draw, inner_rect, fallback or "?", font_for_size(max(8, int((rect[2] - rect[0]) * 0.22))), (255, 255, 255, 210))


def draw_rounded_item_icon(overlay, draw, api_name, rect, fallback, scale):
    draw.rounded_rectangle(rect, radius=6 * scale, fill=(8, 8, 8, 230), outline=(255, 255, 255, 72), width=max(1, int(1.2 * scale)))
    icon = load_item_icon(api_name)
    if icon:
        size = (max(1, int(rect[2] - rect[0] - 4 * scale)), max(1, int(rect[3] - rect[1] - 4 * scale)))
        icon = icon.resize(size)
        overlay.paste(icon.convert("RGBA"), (int(rect[0] + 2 * scale), int(rect[1] + 2 * scale)), icon.convert("RGBA"))
    else:
        draw_centered_text(draw, rect, fallback, font_for_size(max(8, int(8.5 * scale))), (255, 255, 255, 214))


def draw_arrow(draw, rect, scale):
    y = (rect[1] + rect[3]) / 2
    points = [(rect[0], y), (rect[2], y), (rect[2] - 4 * scale, rect[1]), (rect[2], y), (rect[2] - 4 * scale, rect[3])]
    draw.line(points, fill=(255, 255, 255, 98), width=max(1, int(1.4 * scale)))


def draw_tier_pill(draw, tier, rect, scale):
    color = TIER_COLORS.get(tier, ((80, 80, 80), (150, 150, 150)))[1]
    draw.rounded_rectangle(rect, radius=6 * scale, fill=color + (230,), outline=(255, 255, 255, 54), width=1)
    draw_text_center(draw, f"TIER {tier or '?'}", rect, font_for_size(int(11 * scale)), (0, 0, 0, 220))


def draw_trait_list(overlay, draw, traits, rect, scale):
    if not traits:
        draw_text_center(draw, "Traits pending", rect, font_for_size(int(10 * scale)), (255, 255, 255, 122))
        return
    chip_w = 47 * scale
    chip_h = 22 * scale
    gap = 5 * scale
    x = rect[0]
    y = rect[1]
    for index, trait in enumerate(traits[:6]):
        api_name = trait.get("apiName") if isinstance(trait, dict) else ""
        count = trait.get("count") if isinstance(trait, dict) else "-"
        chip = (x, y, x + chip_w, y + chip_h)
        draw.rounded_rectangle(chip, radius=4 * scale, fill=(255, 255, 255, 38))
        icon = load_trait_icon(api_name)
        if icon:
            icon = icon.resize((max(1, int(16 * scale)), max(1, int(16 * scale))))
            overlay.paste(icon.convert("RGBA"), (int(x + 4 * scale), int(y + 3 * scale)), icon.convert("RGBA"))
        draw_text_center(draw, str(count), (chip[2] - 22 * scale, chip[1] + 3 * scale, chip[2] - 4 * scale, chip[3] - 3 * scale), font_for_size(int(11 * scale)), (255, 255, 255, 235))
        x += chip_w + gap
        if x + chip_w > rect[2]:
            x = rect[0]
            y += chip_h + gap


def draw_centered_text(draw, rect, text, font, fill):
    bbox = draw.textbbox((0, 0), str(text), font=font)
    x = (rect[0] + rect[2]) / 2 - (bbox[2] - bbox[0]) / 2
    y = (rect[1] + rect[3]) / 2 - (bbox[3] - bbox[1]) / 2 - bbox[1]
    draw.text((x, y), str(text), font=font, fill=fill)


def draw_text_center(draw, text, rect, font, fill):
    draw_centered_text(draw, rect, text, font, fill)


def cost_color_for(cost):
    try:
        value = int(cost)
    except Exception:
        value = 1
    return COST_COLORS.get(value, COST_COLORS[5])


def short_name(api_name):
    name = str(api_name or "").split("_")[-1]
    return name[:2].upper() if name else "?"


def compact_item_name(api_name):
    name = str(api_name or "").split("_")[-1]
    replacements = {
        "BFSword": "BF Sword",
        "GiantsBelt": "Belt",
        "NegatronCloak": "Cloak",
        "SparringGloves": "Gloves",
        "RecurveBow": "Bow",
        "NeedlesslyLargeRod": "Rod",
        "TearOfTheGoddess": "Tear",
        "ChainVest": "Vest",
        "GargoyleStoneplate": "Stoneplate",
        "RabadonsDeathcap": "Deathcap",
        "StatikkShiv": "Shiv",
        "GuinsoosRageblade": "Guinsoo",
        "InfinityEdge": "IE",
        "LastWhisper": "LW",
        "SpearOfShojin": "Shojin",
        "JeweledGauntlet": "JG",
    }
    return replacements.get(name, name or "Item")


def draw_debug_panel(draw, poll, matches, image_size):
    lines = []
    if poll:
        parsed = poll.get("parsed", {})
        lines.append(f"Offline preview poll: {poll.get('timestamp', '-')}")
        lines.append(f"Stage/game: {parsed.get('gameTime', '-')}")
    if matches:
        lines.append("Tiers: " + " | ".join(f"{int(m.get('slot', 0)) + 1}:{m.get('displayName')}={m.get('tier')}" for m in matches))
    if not lines:
        lines.append("Offline preview: no matching poll data found")

    font = font_for_size(18)
    width = min(image_size[0] - 40, 920)
    height = 26 + 24 * len(lines)
    draw.rounded_rectangle((24, 24, 24 + width, 24 + height), radius=10, fill=(0, 0, 0, 135))
    y = 38
    for line in lines:
        draw.text((40, y), line, font=font, fill=(255, 255, 255, 235))
        y += 24


def scale_rect(rect, scale_x, scale_y):
    x1, y1, x2, y2 = rect
    return (x1 * scale_x, y1 * scale_y, x2 * scale_x, y2 * scale_y)


def inset(rect, amount):
    return (rect[0] + amount, rect[1] + amount, rect[2] - amount, rect[3] - amount)


def hex_points(rect):
    cx = (rect[0] + rect[2]) / 2
    cy = (rect[1] + rect[3]) / 2
    rx = (rect[2] - rect[0]) / 2
    ry = (rect[3] - rect[1]) / 2
    points = []
    for i in range(6):
        angle = math.pi / 6 + i * math.pi / 3
        points.append((cx + math.cos(angle) * rx, cy + math.sin(angle) * ry))
    return points


def lighten(color, amount):
    return tuple(round(c + (255 - c) * amount) for c in color)


def highlight(color, tier, amount):
    target = (255, 255, 255) if tier == "S" else (255, 235, 219)
    return tuple(round(c + (target[i] - c) * amount) for i, c in enumerate(color))


def font_for_size(size):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            pass
    return ImageFont.load_default()


if __name__ == "__main__":
    main()
