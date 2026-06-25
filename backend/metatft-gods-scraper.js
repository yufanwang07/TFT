#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const BASE_URL = "https://www.metatft.com";
const FORCE_REFRESH = process.argv.includes("--force") || process.env.TFT_FORCE_REFRESH === "1";
const OUT_DIR = process.argv.slice(2).find((arg) => !arg.startsWith("--")) || path.join("data", "metatft");
const DEBUG = process.env.METATFT_DEBUG === "1";

const FALLBACK_ENDPOINTS = [
  "https://api-hc.metatft.com/tft-stat-api/god_tiers",
  "https://api-hc.metatft.com/tft-stat-api/god-tiers",
  "https://api-hc.metatft.com/tft-stat-api/gods",
  "https://api-hc.metatft.com/tft-stat-api/gods_tiers",
  "https://api-hc.metatft.com/tft-stat-api/powerups",
  "https://api-hc.metatft.com/tft-stat-api/powerup_tiers",
  "https://api-hc.metatft.com/tft-stat-api/powerups_tiers",
  "https://api-hc.metatft.com/tft-comps-api/god_tiers",
  "https://api-hc.metatft.com/tft-comps-api/god-tiers",
  "https://api-hc.metatft.com/tft-comps-api/gods",
];

async function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const routeHtml = await fetchText(`${BASE_URL}/god-tiers`);
  const routeChunkUrl = findRouteChunkUrl(routeHtml) || await findRouteChunkUrlFromIndex();
  const routeChunk = routeChunkUrl ? await fetchText(routeChunkUrl) : "";
  if (routeChunk && DEBUG) {
    fs.mkdirSync(path.join(OUT_DIR, "debug", "assets"), { recursive: true });
    fs.writeFileSync(path.join(OUT_DIR, "debug", "assets", path.basename(routeChunkUrl)), routeChunk);
  }

  const endpoints = [...new Set([...extractEndpointCandidates(routeChunk), ...FALLBACK_ENDPOINTS])];
  const attempts = [];
  let selected = null;
  for (const endpoint of endpoints) {
    try {
      const payload = await fetchJson(withDefaultParams(endpoint));
      const boons = extractBoons(payload);
      attempts.push({ endpoint, boons: boons.length });
      if (boons.length > 0) {
        selected = { endpoint, payload, boons };
        break;
      }
    } catch (error) {
      attempts.push({ endpoint, error: error.message });
    }
  }

  if (selected == null) {
    const debugPath = path.join(OUT_DIR, "god-tiers-debug.json");
    writeJson(debugPath, { routeChunkUrl, endpoints, attempts });
    throw new Error(`Could not extract god tiers from MetaTFT. Wrote diagnostics to ${debugPath}`);
  }

  const snapshot = {
    source: "metatft",
    sourceUrls: {
      page: `${BASE_URL}/god-tiers`,
      routeChunk: routeChunkUrl || "",
      endpoint: selected.endpoint,
    },
    updated: new Date().toISOString(),
    boons: selected.boons,
    diagnostics: { attempts },
  };
  writeJson(path.join(OUT_DIR, "god-tiers.json"), snapshot);
  console.log(`Wrote ${path.join(OUT_DIR, "god-tiers.json")}`);
  console.log(`Gods: ${selected.boons.length}`);
  console.log(`Source: ${selected.endpoint}`);
}

function findRouteChunkUrl(html) {
  const match = html.match(/assets\/GodTiers-[^"')\s]+\.js/);
  return match ? `${BASE_URL}/${match[0]}` : null;
}

async function findRouteChunkUrlFromIndex() {
  const html = await fetchText(BASE_URL);
  const indexMatch = html.match(/assets\/index-[^"')\s]+\.js/);
  if (!indexMatch) {
    return null;
  }
  const indexUrl = `${BASE_URL}/${indexMatch[0]}`;
  const index = await fetchText(indexUrl);
  return findRouteChunkUrl(index);
}

function extractEndpointCandidates(source) {
  if (!source) {
    return [];
  }
  const candidates = [];
  for (const match of source.matchAll(/https:\/\/api[^"'`\\]+/g)) {
    const url = match[0].replace(/\\u0026/g, "&");
    if (/god|power/i.test(url)) {
      candidates.push(url);
    }
  }
  for (const match of source.matchAll(/["'`](\/tft-[^"'`]+(?:god|power)[^"'`]*)["'`]/gi)) {
    candidates.push(`https://api-hc.metatft.com${match[1]}`);
  }
  return candidates.map((value) => value.replace(/\$\{[^}]+\}/g, "").replace(/\\/g, ""));
}

function withDefaultParams(endpoint) {
  const url = new URL(endpoint);
  if (!url.searchParams.has("queue")) url.searchParams.set("queue", "1100");
  if (!url.searchParams.has("patch")) url.searchParams.set("patch", "current");
  if (!url.searchParams.has("days")) url.searchParams.set("days", "3");
  if (!url.searchParams.has("rank")) url.searchParams.set("rank", "CHALLENGER,DIAMOND,EMERALD,GRANDMASTER,MASTER,PLATINUM");
  if (!url.searchParams.has("permit_filter_adjustment")) url.searchParams.set("permit_filter_adjustment", "true");
  return url.toString();
}

function extractBoons(payload) {
  const tierRows = extractTierContentRows(payload);
  if (tierRows.length > 0) {
    return tierRows;
  }

  const rows = [];
  const seen = new Set();
  visitJson(payload, (value) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return;
    }
    const name = firstString(value, ["name", "displayName", "display_name", "title", "boon", "god", "powerup", "powerUp"]);
    const tier = normalizeTier(firstString(value, ["tier", "tierName", "tier_name", "rank", "level"]));
    if (!name || !tier || !looksLikeBoonRow(value, name)) {
      return;
    }
    const apiName = firstString(value, ["apiName", "api_name", "contentId", "content_id", "id", "slug"]) || slugify(name);
    const normalized = normalizedName(name);
    const key = `${normalized}:${tier}`;
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    const godApiName = normalizeGodApiName(String(apiName), name);
    const displayName = displayNameFromGodApiName(godApiName) || cleanName(name);
    rows.push({
      apiName: godApiName || String(apiName),
      displayName,
      normalizedName: normalizedName(displayName),
      tier,
      avgPlace: numberValue(value.avgPlace ?? value.avg_place ?? value.averagePlacement ?? value.avg_placement),
      playRate: numberValue(value.playRate ?? value.play_rate),
    });
  });
  return rows.sort((a, b) => tierRank(a.tier) - tierRank(b.tier) || a.displayName.localeCompare(b.displayName));
}

function extractTierContentRows(payload) {
  const tiers = payload && payload.content && Array.isArray(payload.content.tiers) ? payload.content.tiers : [];
  const rows = [];
  const seen = new Set();
  for (const tierRow of tiers) {
    const tier = normalizeTier(tierRow && (tierRow.label || tierRow.tier || tierRow.name));
    const content = tierRow && Array.isArray(tierRow.content) ? tierRow.content : [];
    if (!tier || content.length === 0) {
      continue;
    }
    for (const value of content) {
      const rawApiName = typeof value === "string" ? value : firstString(value || {}, ["apiName", "api_name", "contentId", "content_id", "id", "slug"]);
      const rawName = typeof value === "object" && value != null ? firstString(value, ["name", "displayName", "display_name", "title", "god"]) : "";
      const apiName = normalizeGodApiName(rawApiName, rawName);
      const displayName = displayNameFromGodApiName(apiName) || cleanName(rawName);
      if (!apiName || !displayName) {
        continue;
      }
      const key = normalizedName(apiName);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      rows.push({
        apiName,
        displayName,
        normalizedName: normalizedName(displayName),
        tier,
        avgPlace: null,
        playRate: null,
      });
    }
  }
  return rows.sort((a, b) => tierRank(a.tier) - tierRank(b.tier) || a.displayName.localeCompare(b.displayName));
}

function normalizeGodApiName(apiName, fallbackName = "") {
  const raw = String(apiName || "").trim();
  if (/^TFT\d+_God_/i.test(raw)) {
    return raw;
  }
  const fallback = String(fallbackName || "").trim();
  if (/^TFT\d+_God_/i.test(fallback)) {
    return fallback;
  }
  const name = raw || fallback;
  if (!name) {
    return "";
  }
  const cleaned = cleanName(name).replace(/\s+/g, "");
  return cleaned ? `TFT17_God_${cleaned}` : "";
}

function displayNameFromGodApiName(apiName) {
  const suffix = String(apiName || "").replace(/^TFT\d+_God_/i, "");
  if (!suffix || suffix === apiName) {
    return "";
  }
  if (suffix === "AurelionSol") {
    return "Aurelion Sol";
  }
  return suffix.replace(/([a-z])([A-Z])/g, "$1 $2").trim();
}

function looksLikeBoonRow(value, name) {
  const text = `${Object.keys(value).join(" ")} ${name}`.toLowerCase();
  if (/augment|unit|champion|trait|item/.test(text)) {
    return false;
  }
  return /god|boon|power|tier|avg|place|rate|games|count/.test(text);
}

function firstString(value, keys) {
  for (const key of keys) {
    const candidate = value[key];
    if (candidate == null) continue;
    if (typeof candidate === "string" && candidate.trim()) return candidate.trim();
    if (typeof candidate === "number") return String(candidate);
  }
  return "";
}

function normalizeTier(value) {
  if (!value) return "";
  const tier = String(value).trim().toUpperCase();
  if (["X", "S", "A", "B", "C", "D"].includes(tier)) return tier;
  if (tier === "0") return "S";
  if (tier === "1") return "A";
  if (tier === "2") return "B";
  if (tier === "3") return "C";
  if (tier === "4") return "D";
  return "";
}

function cleanName(value) {
  return String(value || "").replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim();
}

function slugify(value) {
  return cleanName(value).replace(/\s+/g, "");
}

function normalizedName(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

function numberValue(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function tierRank(tier) {
  return { X: 0, S: 1, A: 2, B: 3, C: 4, D: 5 }[tier] ?? 99;
}

function visitJson(value, callback) {
  callback(value);
  if (Array.isArray(value)) {
    for (const item of value) visitJson(item, callback);
  } else if (value && typeof value === "object") {
    for (const item of Object.values(value)) visitJson(item, callback);
  }
}

async function fetchJson(url) {
  return JSON.parse(await fetchText(url));
}

async function fetchText(url) {
  const response = await fetch(url, {
    cache: FORCE_REFRESH ? "no-store" : "default",
    headers: {
      "user-agent": "TFTOverlay/0.1 local development scraper",
      "accept": "text/html,application/json,application/javascript",
      ...(FORCE_REFRESH ? { "cache-control": "no-cache", "pragma": "no-cache" } : {}),
    },
  });
  if (!response.ok) {
    throw new Error(`GET ${url} failed: ${response.status} ${response.statusText}`);
  }
  return await response.text();
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
