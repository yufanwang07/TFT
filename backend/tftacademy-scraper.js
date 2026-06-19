#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const BASE_URL = "https://tftacademy.com";
const SET_NUMBER = Number(process.env.TFT_SET || "17");
const OUT_DIR = process.argv[2] || path.join("data", "tftacademy");

async function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const fetchedAt = new Date().toISOString();
  const [augmentsRaw, itemsRaw, compsHtml] = await Promise.all([
    fetchJson(`${BASE_URL}/api/tierlist/augments?set=${SET_NUMBER}`),
    fetchJson(`${BASE_URL}/api/tierlist/items?set=${SET_NUMBER}`),
    fetchText(`${BASE_URL}/tierlist/comps`),
  ]);
  const staticData = await fetchJson("https://raw.communitydragon.org/latest/cdragon/tft/en_us.json");
  const augmentNamesByApiName = buildAugmentNameIndex(staticData);

  const compsRaw = extractCompsFromSveltePage(compsHtml);
  const augments = normalizeAugments(augmentsRaw.augments_tierlists || [], augmentNamesByApiName);
  const items = normalizeItems(itemsRaw.items_tierlists || []);
  const comps = normalizeComps(compsRaw);

  const snapshot = {
    source: "tftacademy",
    sourceUrls: {
      comps: `${BASE_URL}/tierlist/comps`,
      augments: `${BASE_URL}/tierlist/augments`,
    items: `${BASE_URL}/tierlist/items`,
    augmentApi: `${BASE_URL}/api/tierlist/augments?set=${SET_NUMBER}`,
      itemApi: `${BASE_URL}/api/tierlist/items?set=${SET_NUMBER}`,
      augmentStaticData: "https://raw.communitydragon.org/latest/cdragon/tft/en_us.json",
    },
    set: SET_NUMBER,
    fetchedAt,
    augments,
    items,
    comps,
    indexes: {
      augmentsByApiName: buildAugmentIndex(augments),
      itemsByApiName: buildItemIndex(items),
      compsBySlug: Object.fromEntries(comps.map((comp) => [comp.slug, comp])),
    },
  };

  writeJson(path.join(OUT_DIR, "latest.json"), snapshot);
  writeJson(path.join(OUT_DIR, `snapshot-${fetchedAt.replace(/[:.]/g, "-")}.json`), snapshot);
  console.log(`Wrote ${path.join(OUT_DIR, "latest.json")}`);
  console.log(`Augments: ${augments.length} records, items: ${items.length} records, comps: ${comps.length} comps`);
}

async function fetchText(url) {
  const response = await fetch(url, {
    headers: {
      "user-agent": "TFTOverlay/0.1 local development scraper",
      "accept": "text/html,application/json",
    },
  });
  if (!response.ok) {
    throw new Error(`GET ${url} failed: ${response.status} ${response.statusText}`);
  }
  return await response.text();
}

async function fetchJson(url) {
  return JSON.parse(await fetchText(url));
}

function extractCompsFromSveltePage(html) {
  const start = html.indexOf("kit.start(app, element, {");
  if (start === -1) {
    throw new Error("Could not find Svelte boot payload in comps page.");
  }

  const dataKey = html.indexOf("data:", start);
  const dataArraySource = extractBalancedArray(html, dataKey);
  const records = vm.runInNewContext(`(${dataArraySource})`, {}, { timeout: 1000 });
  for (const record of records) {
    if (record && record.data && Array.isArray(record.data.guides)) {
      return record.data.guides;
    }
  }
  return [];
}

function extractBalancedArray(source, fromIndex) {
  const start = source.indexOf("[", fromIndex);
  let depth = 0;
  let quote = null;
  let escaped = false;

  for (let i = start; i < source.length; i += 1) {
    const char = source[i];
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === quote) {
        quote = null;
      }
      continue;
    }

    if (char === "\"" || char === "'" || char === "`") {
      quote = char;
    } else if (char === "[") {
      depth += 1;
    } else if (char === "]") {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start, i + 1);
      }
    }
  }

  throw new Error("Could not extract balanced Svelte data array.");
}

function normalizeAugments(records, augmentNamesByApiName) {
  const normalized = [];
  for (const record of records) {
    for (const [tier, apiNames] of Object.entries(record.tier || {})) {
      for (const apiName of apiNames || []) {
        normalized.push({
          apiName,
          displayName: augmentNamesByApiName[apiName] || displayNameFromApiName(apiName),
          tier,
          stage: record.stage,
          augmentTier: record.augmenttier,
          set: record.set,
          updated: record.updated,
        });
      }
    }
  }
  return normalized.sort(compareAugments);
}

function buildAugmentNameIndex(staticData) {
  const index = {};
  const records = [];
  records.push(...(staticData.items || []));
  for (const set of staticData.setData || []) {
    records.push(...(set.augments || []), ...(set.items || []));
  }

  for (const record of records) {
    if (!record || !record.apiName || !record.name || record.name.includes("_Name")) {
      continue;
    }
    index[record.apiName] = record.name;
  }
  return index;
}

function displayNameFromApiName(apiName) {
  return String(apiName || "")
    .replace(/^TFT\d*_?/, "")
    .replace(/^Augment_/, "")
    .replace(/_PAIRS$/, "")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/(\D)(\d)$/g, "$1 $2")
    .replace(/_/g, " ")
    .trim();
}

function normalizeItems(records) {
  const normalized = [];
  for (const record of records) {
    for (const [tier, apiNames] of Object.entries(record.tier || {})) {
      for (const apiName of apiNames || []) {
        normalized.push({
          apiName,
          tier,
          type: record.type,
          set: record.set,
          updated: record.updated,
        });
      }
    }
  }
  return normalized.sort((a, b) => `${a.type}:${a.tier}:${a.apiName}`.localeCompare(`${b.type}:${b.tier}:${b.apiName}`));
}

function normalizeComps(guides) {
  return guides.map((guide) => ({
    id: guide.id,
    slug: guide.compSlug || "",
    title: guide.title || guide.metaTitle || "",
    metaTitle: guide.metaTitle || "",
    tier: guide.tier || "",
    style: guide.style || "",
    difficulty: guide.difficulty || "",
    mainChampion: guide.mainChampion || null,
    mainAugment: guide.mainAugment || null,
    augmentTypes: guide.augmentTypes || [],
    augments: apiNames(guide.augments),
    overlayAugments: apiNames(guide.overlayAugments),
    carousel: apiNames(guide.carousel),
    finalComp: guide.finalComp || [],
    earlyComp: guide.earlyComp || [],
    tips: guide.tips || [],
    updated: guide.updated || null,
  })).sort((a, b) => tierRank(a.tier) - tierRank(b.tier) || a.title.localeCompare(b.title));
}

function buildAugmentIndex(augments) {
  const index = {};
  for (const augment of augments) {
    index[augment.apiName] ||= [];
    index[augment.apiName].push({
      tier: augment.tier,
      stage: augment.stage,
      augmentTier: augment.augmentTier,
      updated: augment.updated,
    });
  }
  return index;
}

function buildItemIndex(items) {
  const index = {};
  for (const item of items) {
    index[item.apiName] ||= [];
    index[item.apiName].push({
      tier: item.tier,
      type: item.type,
      updated: item.updated,
    });
  }
  return index;
}

function apiNames(values) {
  return (values || []).map((value) => value.apiName || value).filter(Boolean);
}

function compareAugments(a, b) {
  return `${a.stage}:${a.augmentTier}:${tierRank(a.tier)}:${a.apiName}`.localeCompare(`${b.stage}:${b.augmentTier}:${tierRank(b.tier)}:${b.apiName}`);
}

function tierRank(tier) {
  return { S: 0, A: 1, B: 2, C: 3, D: 4, X: 5 }[tier] ?? 99;
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
