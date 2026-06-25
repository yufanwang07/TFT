#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const BASE_URL = "https://www.metatft.com";
const UNIT_ITEMS_ENDPOINT = "https://api-hc.metatft.com/tft-comps-api/unit_items_processed";
const UNIT_DETAIL_ITEMS_ENDPOINT = "https://api-hc.metatft.com/tft-stat-api/unit_detail_items";
const SHOULD_LIST_UNITS = process.argv.includes("--list-units");
const FORCE_REFRESH = process.argv.includes("--force") || process.env.TFT_FORCE_REFRESH === "1";
const OUT_DIR = process.argv.slice(2).find((arg) => !arg.startsWith("--")) || path.join("data", "metatft");
const UNIT_TARGETS = unitTargetsFromEnvironmentOrLocalCache();
const DEBUG = process.env.METATFT_DEBUG === "1";
const DUMP_HTML = process.env.METATFT_DUMP_HTML === "1";
const DUMP_UNITS = new Set((process.env.METATFT_DUMP_UNITS || "").split(",").map((value) => value.trim()).filter(Boolean));

async function main() {
  if (SHOULD_LIST_UNITS) {
    console.log(JSON.stringify(UNIT_TARGETS, null, 2));
    return;
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const existing = FORCE_REFRESH ? { units: [] } : readExisting();
  if (FORCE_REFRESH) {
    console.log("Force refresh enabled; existing MetaTFT builds will not be reused.");
  }
  const localFallbacks = localBuildsFromTftAcademy();
  const metatftUnitItems = await fetchMetaTFTUnitItems();
  if (DUMP_HTML) {
    dumpApiDiagnostics(metatftUnitItems);
  }
  const units = [];
  const diagnostics = {
    targetUnits: UNIT_TARGETS.length,
    scrapedFromMetaTFT: 0,
    noMetaTFTBuilds: 0,
    reusedExisting: 0,
    filledFromTftAcademy: 0,
    empty: 0,
    failed: 0,
    emptyUnits: [],
    failedUnits: [],
  };
  console.log(`Target units: ${UNIT_TARGETS.length}`);
  for (const target of UNIT_TARGETS) {
    try {
      const topItems = topItemsFromMetaTFTUnitItems(target, metatftUnitItems);
      const unit = await scrapeUnitDetail(target, topItems) || await scrapeUnit(target, topItems);
      if (unit.builds.length > 0) {
        diagnostics.scrapedFromMetaTFT += 1;
        units.push(unit);
        debugStatus(target, `metatft ${unit.builds.length}`);
      } else {
        diagnostics.noMetaTFTBuilds += 1;
        const fallback = findExistingUnit(existing, target) || findLocalFallbackUnit(localFallbacks, target);
        if (fallback) {
          diagnostics[fallback.source === "tftacademy" ? "filledFromTftAcademy" : "reusedExisting"] += 1;
          units.push(fallback);
          debugStatus(target, `${fallback.source || "existing"} ${fallback.builds.length}`);
        } else {
          diagnostics.empty += 1;
          diagnostics.emptyUnits.push(target.slug);
          debugStatus(target, "empty");
        }
      }
    } catch (error) {
      console.warn(`MetaTFT scrape failed for ${target.slug}: ${error.message}`);
      diagnostics.failed += 1;
      diagnostics.failedUnits.push({ slug: target.slug, error: error.message });
      const fallback = findExistingUnit(existing, target) || findLocalFallbackUnit(localFallbacks, target);
      if (fallback) {
        diagnostics[fallback.source === "tftacademy" ? "filledFromTftAcademy" : "reusedExisting"] += 1;
        units.push(fallback);
        debugStatus(target, `${fallback.source || "existing"} ${fallback.builds.length} after failure`);
      } else {
        diagnostics.empty += 1;
        diagnostics.emptyUnits.push(target.slug);
      }
    }
  }

  const snapshot = {
    source: "metatft",
    sourceUrls: {
      units: `${BASE_URL}/units/`,
      unitItems: UNIT_ITEMS_ENDPOINT,
      unitDetailItems: UNIT_DETAIL_ITEMS_ENDPOINT,
      localFallback: "data/tftacademy/latest.json",
    },
    updated: new Date().toISOString(),
    diagnostics,
    units,
  };
  writeJson(path.join(OUT_DIR, "latest.json"), snapshot);
  console.log(`Wrote ${path.join(OUT_DIR, "latest.json")}`);
  console.log(`Units: ${units.length}`);
  console.log(`MetaTFT scraped: ${diagnostics.scrapedFromMetaTFT}`);
  console.log(`MetaTFT pages with no extracted builds: ${diagnostics.noMetaTFTBuilds}`);
  console.log(`Existing fallback: ${diagnostics.reusedExisting}`);
  console.log(`TFTAcademy fallback: ${diagnostics.filledFromTftAcademy}`);
  if (diagnostics.empty > 0) {
    console.log(`No builds: ${diagnostics.empty} (${diagnostics.emptyUnits.slice(0, 12).join(", ")}${diagnostics.emptyUnits.length > 12 ? ", ..." : ""})`);
  }
}

async function scrapeUnit(target, topItems = []) {
  const slug = target.slug;
  const url = `${BASE_URL}/units/${encodeURIComponent(slug)}`;
  const html = await fetchText(url);
  if (shouldDumpHtml(slug)) {
    await dumpHtmlDiagnostics(target, html);
  }
  return {
    name: target.name || displayNameFromSlug(slug),
    slug,
    sourceUrl: url,
    ...(topItems.length > 0 ? { topItems } : {}),
    builds: extractBuilds(html).slice(0, 8),
  };
}

async function scrapeUnitDetail(target, topItems = []) {
  const unitApiName = target.apiName || `TFT17_${target.slug}`;
  const url = unitDetailItemsUrl(unitApiName);
  let payload = null;
  try {
    payload = await fetchJson(url);
  } catch (error) {
    if (shouldDumpHtml(target.slug)) {
      console.warn(`MetaTFT unit-detail-items API failed for ${target.slug}: ${error.message}`);
    }
    debugStatus(target, `unit_detail_items failed: ${error.message}`);
    return null;
  }
  if (shouldDumpHtml(target.slug)) {
    dumpUnitDetailDiagnostics(target, payload);
  }
  const builds = extractItemSetBuildsFromObjects([payload]).slice(0, 8);
  if (builds.length === 0) {
    return null;
  }

  return {
    name: target.name || displayNameFromSlug(target.slug),
    slug: target.slug,
    sourceUrl: url,
    source: "metatft",
    ...(topItems.length > 0 ? { topItems } : {}),
    builds,
  };
}

function unitDetailItemsUrl(unitApiName) {
  const params = new URLSearchParams();
  params.set("queue", "1100");
  params.set("patch", "current");
  params.set("days", "3");
  params.set("rank", "CHALLENGER,DIAMOND,EMERALD,GRANDMASTER,MASTER,PLATINUM");
  params.set("permit_filter_adjustment", "true");
  params.set("unit", unitApiName);
  params.set("artifact_count", "0");
  return `${UNIT_DETAIL_ITEMS_ENDPOINT}?${params.toString()}`;
}

async function fetchMetaTFTUnitItems() {
  try {
    return await fetchJson(UNIT_ITEMS_ENDPOINT);
  } catch (error) {
    console.warn(`MetaTFT unit-items API failed: ${error.message}`);
    return null;
  }
}

async function fetchJson(url) {
  const text = await fetchText(url);
  return JSON.parse(text);
}

async function fetchText(url) {
  const response = await fetch(url, {
    cache: FORCE_REFRESH ? "no-store" : "default",
    headers: {
      "user-agent": "TFTOverlay/0.1 local development scraper",
      "accept": "text/html,application/json",
      ...(FORCE_REFRESH ? { "cache-control": "no-cache", "pragma": "no-cache" } : {}),
    },
  });
  if (!response.ok) {
    throw new Error(`GET ${url} failed: ${response.status} ${response.statusText}`);
  }
  return await response.text();
}

function topItemsFromMetaTFTUnitItems(target, payload) {
  if (!payload) {
    return [];
  }

  const entries = findUnitItemEntries(payload, target);
  const topItems = [];
  const seen = new Set();
  for (const entry of entries) {
    const items = Array.isArray(entry && entry.items) ? entry.items : [];
    for (const item of items) {
      const itemName = itemApiNameFromValue(item);
      if (!itemName || seen.has(itemName) || /_Item_Empty|_Item_Unknown|AnyItem/i.test(itemName)) {
        continue;
      }
      seen.add(itemName);
      topItems.push(itemName);
      if (topItems.length >= 12) {
        return topItems;
      }
    }
  }
  return topItems;
}

function findUnitItemEntries(payload, target) {
  const keys = unitKeyCandidates(target);
  const entries = [];
  const directContainers = [payload.units, payload.unit_items, payload.data, payload.results, payload.content].filter((value) => value && typeof value === "object");
  for (const container of directContainers) {
    for (const key of keys) {
      if (Object.prototype.hasOwnProperty.call(container, key)) {
        entries.push(container[key]);
      }
    }
    for (const [key, value] of Object.entries(container)) {
      if (keys.has(normalize(key))) {
        entries.push(value);
      }
    }
  }

  visitJson(payload, (value) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return;
    }
    const valueUnit = value.unit || value.apiName || value.character_id || value.characterId || value.name;
    if (valueUnit && keys.has(normalize(valueUnit))) {
      entries.push(value);
    }
  });

  return entries;
}

function unitKeyCandidates(target) {
  return new Set([
    target.slug,
    target.name,
    target.apiName,
    target.apiName && target.apiName.replace(/^TFT\d+_/i, ""),
    `TFT17_${target.slug}`,
  ].filter(Boolean).map(normalize));
}

function extractItemSetBuildsFromObjects(entries) {
  const builds = [];
  const seen = new Set();
  for (const entry of entries) {
    visitJson(entry, (value) => {
      if (!value || typeof value !== "object") {
        return;
      }

      const items = itemSetFromBuildLikeValue(value);
      if (items.length !== 3) {
        return;
      }

      const key = items.join("|");
      if (seen.has(key)) {
        return;
      }
      seen.add(key);
      const placementStats = placementStatsFromPlaces(value.places);
      builds.push({
        items,
        source: "metatft",
        avgPlace: numericValue(value.avg_place ?? value.avgPlace ?? value.avg ?? value.place) ?? placementStats.avgPlace,
        placeChange: numericValue(value.place_change ?? value.placeChange ?? value.delta),
        playRate: numericValue(value.play_rate ?? value.playRate ?? value.pcnt ?? value.percent),
        count: numericValue(value.total ?? value.count) ?? placementStats.count,
        score: numericValue(value.score ?? value.build_score ?? value.total ?? value.count) ?? placementStats.count,
      });
    });
  }

  return builds.sort((left, right) => (right.score ?? 0) - (left.score ?? 0));
}

function placementStatsFromPlaces(places) {
  if (!Array.isArray(places) || places.length === 0) {
    return { avgPlace: null, count: null };
  }
  let count = 0;
  let weighted = 0;
  for (let index = 0; index < places.length; index += 1) {
    const value = Number(places[index]);
    if (!Number.isFinite(value)) {
      continue;
    }
    count += value;
    weighted += value * (index + 1);
  }
  return {
    avgPlace: count > 0 ? weighted / count : null,
    count: count > 0 ? count : null,
  };
}

function itemSetFromBuildLikeValue(value) {
  const candidate = value.buildNames || value.build_names || value.build_items || value.buildItems || value.buildName || value.item_names || value.itemNames || value.items || value.item_list || value.itemList;
  if (!candidate) {
    return [];
  }

  const rawItems = Array.isArray(candidate) ? candidate : String(candidate).split(/[|,>+/ ]+/);
  if (rawItems.length !== 3) {
    return [];
  }
  const items = rawItems
    .map(itemApiNameFromValue)
    .filter(Boolean)
    .filter((item) => !/_Item_Empty|_Item_Unknown|AnyItem|TFT_Flex/i.test(item));
  return items.length === 3 ? items : [];
}

function itemApiNameFromValue(value) {
  if (value && typeof value === "object") {
    return itemApiNameFromValue(value.itemName || value.apiName || value.item || value.name || value.id);
  }
  const text = String(value || "").trim();
  if (!text) {
    return "";
  }
  if (/^TFT(?:\d+)?_Item_/i.test(text)) {
    return text;
  }
  return text;
}

function numericValue(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function visitJson(value, callback, seen = new Set()) {
  if (value === null || typeof value !== "object" || seen.has(value)) {
    return;
  }
  seen.add(value);
  callback(value);
  if (Array.isArray(value)) {
    for (const item of value) {
      visitJson(item, callback, seen);
    }
    return;
  }
  for (const child of Object.values(value)) {
    visitJson(child, callback, seen);
  }
}

function shouldDumpHtml(slug) {
  return DUMP_HTML && (DUMP_UNITS.size === 0 || DUMP_UNITS.has(slug));
}

async function dumpHtmlDiagnostics(target, html) {
  const debugDir = path.join(OUT_DIR, "debug");
  fs.mkdirSync(debugDir, { recursive: true });
  const htmlPath = path.join(debugDir, `${target.slug}.html`);
  const summaryPath = path.join(debugDir, `${target.slug}.summary.json`);
  fs.writeFileSync(htmlPath, html);
  const summary = htmlSummary(html);
  summary.assetSummaries = await dumpReferencedAssets(target, html, debugDir);
  writeJson(summaryPath, summary);
  console.log(`Dumped MetaTFT HTML for ${target.slug}: ${htmlPath}`);
}

function dumpApiDiagnostics(unitItemsPayload) {
  const debugDir = path.join(OUT_DIR, "debug");
  fs.mkdirSync(debugDir, { recursive: true });
  if (unitItemsPayload) {
    const filePath = path.join(debugDir, "unit_items_processed.json");
    writeJson(filePath, unitItemsPayload);
    writeJson(path.join(debugDir, "unit_items_processed.summary.json"), apiPayloadSummary(unitItemsPayload));
    console.log(`Dumped MetaTFT unit-items API: ${filePath}`);
  }
}

function dumpUnitDetailDiagnostics(target, payload) {
  const debugDir = path.join(OUT_DIR, "debug");
  fs.mkdirSync(debugDir, { recursive: true });
  const filePath = path.join(debugDir, `${target.slug}.unit_detail_items.json`);
  writeJson(filePath, payload);
  writeJson(path.join(debugDir, `${target.slug}.unit_detail_items.summary.json`), apiPayloadSummary(payload));
  console.log(`Dumped MetaTFT unit detail for ${target.slug}: ${filePath}`);
}

function apiPayloadSummary(payload) {
  const topLevelKeys = payload && typeof payload === "object" && !Array.isArray(payload) ? Object.keys(payload) : [];
  const keyCounts = {};
  const itemFields = [];
  visitJson(payload, (value) => {
    for (const key of Object.keys(value)) {
      keyCounts[key] = (keyCounts[key] || 0) + 1;
    }
    const items = itemSetFromBuildLikeValue(value);
    if (items.length > 0 && itemFields.length < 40) {
      itemFields.push({
        keys: Object.keys(value).slice(0, 20),
        items,
        unit: value.unit || value.apiName || value.character_id || value.characterId || value.name || null,
      });
    }
  });
  return {
    topLevelKeys,
    topLevelShape: describeJsonShape(payload),
    commonKeys: Object.entries(keyCounts).sort((left, right) => right[1] - left[1]).slice(0, 80),
    sampleItemFields: itemFields,
  };
}

function describeJsonShape(value) {
  if (Array.isArray(value)) {
    return { type: "array", length: value.length, first: describeJsonShape(value[0]) };
  }
  if (!value || typeof value !== "object") {
    return { type: typeof value };
  }
  const result = { type: "object", keys: Object.keys(value).slice(0, 40) };
  for (const key of Object.keys(value).slice(0, 8)) {
    const child = value[key];
    result[key] = Array.isArray(child) ? `array(${child.length})` : child && typeof child === "object" ? `object(${Object.keys(child).length})` : typeof child;
  }
  return result;
}

function htmlSummary(html) {
  const title = firstMatch(html, /<title[^>]*>(.*?)<\/title>/is);
  const scriptSrcs = [...html.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)].map((match) => match[1]).slice(0, 60);
  const itemApiNames = [...new Set([...html.matchAll(/TFT(?:\d+)?_Item_[A-Za-z0-9_]+/g)].map((match) => match[0]))];
  const lower = html.toLowerCase();
  return {
    bytes: Buffer.byteLength(html),
    title: stripTags(title || ""),
    hasNextData: /<script[^>]+id=["']__NEXT_DATA__["']/i.test(html),
    scriptSrcs,
    uniqueItemApiNameCount: itemApiNames.length,
    uniqueItemApiNames: itemApiNames.slice(0, 80),
    keywordCounts: {
      item: countSubstring(lower, "item"),
      build: countSubstring(lower, "build"),
      recommended: countSubstring(lower, "recommended"),
      unit: countSubstring(lower, "unit"),
      missFortune: countSubstring(lower, "missfortune"),
      deathblade: countSubstring(lower, "deathblade"),
    },
    snippets: [
      snippetAround(html, "item"),
      snippetAround(html, "build"),
      snippetAround(html, "__NEXT_DATA__"),
      snippetAround(html, "self.__next_f.push"),
      snippetAround(html, "Deathblade"),
      snippetAround(html, "MissFortune"),
    ].filter(Boolean),
  };
}

async function dumpReferencedAssets(target, html, debugDir) {
  const assetDir = path.join(debugDir, "assets");
  fs.mkdirSync(assetDir, { recursive: true });
  const assetUrls = [...new Set(extractScriptSrcs(html).filter((src) => /\.js(?:$|\?)/i.test(src)))];
  const summaries = [];
  for (let index = 0; index < assetUrls.length; index += 1) {
    const src = assetUrls[index];
    const url = absoluteUrl(src);
    const fileName = safeFileName(path.basename(src.split("?")[0]) || "asset.js");
    const filePath = path.join(assetDir, fileName);
    try {
      const text = await fetchText(url);
      fs.writeFileSync(filePath, text);
      summaries.push({
        src,
        url,
        path: filePath,
        bytes: Buffer.byteLength(text),
        ...assetTextSummary(text),
      });
      for (const lazyAsset of extractRelevantLazyAssets(text)) {
        if (!assetUrls.includes(lazyAsset)) {
          assetUrls.push(lazyAsset);
        }
      }
      console.log(`Dumped MetaTFT asset for ${target.slug}: ${filePath}`);
    } catch (error) {
      summaries.push({ src, url, error: error.message });
    }
  }
  return summaries;
}

function extractRelevantLazyAssets(text) {
  const assets = [...new Set([...text.matchAll(/["'](assets\/[^"']+\.js)["']/g)].map((match) => match[1]))];
  return assets.filter((asset) => /Units|ItemsScatter|UnitSearchFilter|Items-/i.test(asset));
}

function extractScriptSrcs(html) {
  return [...html.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)].map((match) => match[1]);
}

function absoluteUrl(src) {
  if (/^https?:\/\//i.test(src)) {
    return src;
  }
  if (src.startsWith("//")) {
    return `https:${src}`;
  }
  return new URL(src, BASE_URL).toString();
}

function safeFileName(value) {
  return String(value || "asset.js").replace(/[^A-Za-z0-9._-]/g, "_");
}

function assetTextSummary(text) {
  const strings = extractInterestingStrings(text);
  const endpoints = strings.filter((value) => looksLikeEndpoint(value));
  const dataMetatft = strings.filter((value) => value.includes("data.metatft.com"));
  const apiLike = strings.filter((value) => /api|graphql|query|units|champion|items|stats|build/i.test(value));
  const itemApiNames = [...new Set([...text.matchAll(/TFT(?:\d+)?_Item_[A-Za-z0-9_]+/g)].map((match) => match[0]))];
  return {
    uniqueItemApiNameCount: itemApiNames.length,
    uniqueItemApiNames: itemApiNames.slice(0, 80),
    endpointCandidates: [...new Set(endpoints)].slice(0, 120),
    dataMetatftCandidates: [...new Set(dataMetatft)].slice(0, 120),
    apiStringCandidates: [...new Set(apiLike)].slice(0, 160),
    snippets: [
      snippetAround(text, "data.metatft.com"),
      snippetAround(text, "units"),
      snippetAround(text, "champion"),
      snippetAround(text, "recommended"),
      snippetAround(text, "itemBuild"),
      snippetAround(text, "items"),
      snippetAround(text, "MissFortune"),
      snippetAround(text, "Deathblade"),
    ].filter(Boolean),
  };
}

function extractInterestingStrings(text) {
  const strings = [];
  for (const match of text.matchAll(/["'`]([^"'`]{3,240})["'`]/g)) {
    const value = match[1]
      .replace(/\\u002F/g, "/")
      .replace(/\\\//g, "/")
      .replace(/\\n/g, " ")
      .trim();
    if (value) {
      strings.push(value);
    }
  }
  return strings;
}

function looksLikeEndpoint(value) {
  return /^https?:\/\//i.test(value) || value.startsWith("/api/") || value.startsWith("/graphql") || value.startsWith("/data/") || value.startsWith("data/");
}

function firstMatch(value, regex) {
  const match = regex.exec(value);
  return match ? match[1] : "";
}

function stripTags(value) {
  return String(value || "").replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
}

function countSubstring(value, needle) {
  let count = 0;
  let offset = 0;
  while (needle && (offset = value.indexOf(needle, offset)) !== -1) {
    count += 1;
    offset += needle.length;
  }
  return count;
}

function snippetAround(value, needle) {
  const index = value.toLowerCase().indexOf(String(needle).toLowerCase());
  if (index === -1) {
    return null;
  }
  const start = Math.max(0, index - 240);
  const end = Math.min(value.length, index + 360);
  return {
    needle,
    text: stripTags(value.slice(start, end)),
  };
}

function extractBuilds(html) {
  const apiNames = [...html.matchAll(/TFT(?:\d+)?_Item_[A-Za-z0-9_]+/g)].map((match) => match[0]);
  const builds = [];
  const seen = new Set();
  for (let index = 0; index + 2 < apiNames.length; index += 1) {
    const items = apiNames.slice(index, index + 3);
    if (items.some((item) => /_Item_Empty|_Item_Unknown/i.test(item))) {
      continue;
    }
    const key = items.join("|");
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    builds.push({ items });
    if (builds.length >= 8) {
      break;
    }
  }
  return builds;
}

function readExisting() {
  const filePath = path.join(OUT_DIR, "latest.json");
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return { units: [] };
  }
}

function localBuildsFromTftAcademy() {
  const filePath = path.join("data", "tftacademy", "latest.json");
  let snapshot = null;
  try {
    snapshot = JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return new Map();
  }

  const byUnit = new Map();
  for (const comp of snapshot.comps || []) {
    for (const champion of comp.finalComp || []) {
      addLocalBuild(byUnit, champion, comp, "final");
    }
    for (const champion of comp.earlyComp || []) {
      addLocalBuild(byUnit, champion, comp, "early");
    }
  }

  const fallbackUnits = new Map();
  for (const [key, builds] of byUnit.entries()) {
    const seen = new Set();
    const uniqueBuilds = [];
    for (const build of builds) {
      const buildKey = build.items.join("|");
      if (seen.has(buildKey)) {
        continue;
      }
      seen.add(buildKey);
      uniqueBuilds.push(build);
      if (uniqueBuilds.length >= 8) {
        break;
      }
    }
    fallbackUnits.set(key, uniqueBuilds);
  }
  return fallbackUnits;
}

function addLocalBuild(byUnit, champion, comp, phase) {
  const items = (champion.items || []).filter((item) => item && !/_Item_Empty|_Item_Unknown|AnyItem|TFT_Flex/i.test(item));
  if (items.length === 0 || isNonChampion(champion)) {
    return;
  }
  if (items.length !== 3) {
    return;
  }

  const key = normalize(apiSuffixFromChampion(champion) || champion.name);
  const builds = byUnit.get(key) || [];
  builds.push({
    items,
    source: "tftacademy",
    phase,
    compTitle: comp.title || comp.metaTitle || "",
    compTier: comp.tier || "",
  });
  byUnit.set(key, builds);
}

function findLocalFallbackUnit(localFallbacks, target) {
  const builds = localFallbacks.get(normalize(target.slug)) || localFallbacks.get(normalize(target.name));
  if (!builds || builds.length === 0) {
    return null;
  }

  return {
    name: target.name || displayNameFromSlug(target.slug),
    slug: target.slug,
    source: "tftacademy",
    builds,
  };
}

function unitTargetsFromEnvironmentOrLocalCache() {
  const fromEnv = (process.env.METATFT_UNITS || "").split(",").map((value) => value.trim()).filter(Boolean);
  if (fromEnv.length > 0) {
    return uniqueTargets(fromEnv.map((value) => ({ name: displayNameFromSlug(value), slug: slugFromValue(value) })));
  }

  const targets = [];
  addTargetsFromTftAcademySnapshot(targets);
  addTargetsFromChampionIconCache(targets);
  const discovered = uniqueTargets(targets).sort((left, right) => left.name.localeCompare(right.name));
  return discovered.length > 0 ? discovered : [{ name: "Miss Fortune", slug: "MissFortune" }];
}

function addTargetsFromTftAcademySnapshot(targets) {
  const filePath = path.join("data", "tftacademy", "latest.json");
  let snapshot = null;
  try {
    snapshot = JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return;
  }

  for (const comp of snapshot.comps || []) {
    addChampionTarget(targets, comp.mainChampion);
    for (const champion of comp.finalComp || []) {
      addChampionTarget(targets, champion);
    }
    for (const champion of comp.earlyComp || []) {
      addChampionTarget(targets, champion);
    }
  }
}

function addTargetsFromChampionIconCache(targets) {
  const dirPath = path.join("data", "tftacademy", "champions");
  let fileNames = [];
  try {
    fileNames = fs.readdirSync(dirPath);
  } catch {
    return;
  }

  for (const fileName of fileNames) {
    const apiName = fileName.replace(/\.(?:png|webp|jpg|jpeg)$/i, "");
    addChampionTarget(targets, { apiName });
  }
}

function addChampionTarget(targets, champion) {
  if (!champion || isNonChampion(champion)) {
    return;
  }

  const apiSuffix = apiSuffixFromChampion(champion);
  const slug = slugFromValue(apiSuffix || champion.name);
  if (!slug) {
    return;
  }

  targets.push({
    apiName: champion.apiName || (apiSuffix ? `TFT17_${apiSuffix}` : ""),
    name: champion.name || displayNameFromSlug(slug),
    slug,
  });
}

function apiSuffixFromChampion(champion) {
  return String(champion.apiName || "")
    .replace(/^TFT\d+_/i, "")
    .replace(/^TFT_/i, "");
}

function isNonChampion(champion) {
  const haystack = `${champion.apiName || ""} ${champion.name || ""}`.toLowerCase();
  return /fakeunit|summon|minion|relic|flex|black hole|bia.*bayin/.test(haystack);
}

function slugFromValue(value) {
  const raw = String(value || "").replace(/^TFT\d+_/i, "").replace(/^TFT_/i, "");
  if (!raw.trim()) {
    return "";
  }

  return raw
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");
}

function uniqueTargets(targets) {
  const bySlug = new Map();
  for (const target of targets) {
    const slug = slugFromValue(target.slug || target.name);
    if (!slug || bySlug.has(normalize(slug))) {
      continue;
    }
    bySlug.set(normalize(slug), {
      apiName: target.apiName || "",
      name: target.name || displayNameFromSlug(slug),
      slug,
    });
  }
  return [...bySlug.values()];
}

function findExistingUnit(existing, target) {
  const normalized = normalize(target.slug || target.name);
  const unit = (existing.units || []).find((candidate) => normalize(candidate.slug || candidate.name) === normalized || normalize(candidate.name) === normalize(target.name));
  if (!unit) {
    return null;
  }

  const builds = sanitizeBuilds(unit.builds || []);
  if (builds.length === 0) {
    return null;
  }
  return {
    ...unit,
    builds,
  };
}

function sanitizeBuilds(builds) {
  const seen = new Set();
  const sanitized = [];
  for (const build of builds || []) {
    const items = itemSetFromBuildLikeValue(build);
    if (items.length !== 3) {
      continue;
    }
    const key = items.join("|");
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    sanitized.push({
      ...build,
      items,
    });
  }
  return sanitized;
}

function debugStatus(target, status) {
  if (DEBUG) {
    console.log(`[debug] ${target.slug}: ${status}`);
  }
}

function displayNameFromSlug(slug) {
  return String(slug || "")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/_/g, " ")
    .trim();
}

function normalize(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
