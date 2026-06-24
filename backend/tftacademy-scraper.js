#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const BASE_URL = "https://tftacademy.com";
const ASSETS_BASE_URL = "https://assets.tftacademy.com";
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
  const championInfoByApiName = buildChampionInfoIndex(staticData);
  const traitInfoByApiName = buildTraitInfoIndex(staticData, SET_NUMBER);
  const itemInfoByApiName = buildItemInfoIndex(staticData);

  const compsRaw = extractCompsFromSveltePage(compsHtml);
  const augments = normalizeAugments(augmentsRaw.augments_tierlists || [], augmentNamesByApiName);
  const items = normalizeItems(itemsRaw.items_tierlists || [], itemInfoByApiName);
  const champions = normalizeChampions(championInfoByApiName, SET_NUMBER);
  const comps = normalizeComps(compsRaw, championInfoByApiName, traitInfoByApiName, itemInfoByApiName);
  const championIconCount = await downloadChampionIcons(comps, OUT_DIR);
  const itemIconCount = await downloadItemIcons(items, comps, OUT_DIR);
  const traitIconCount = await downloadTraitIcons(comps, OUT_DIR);

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
    champions,
    comps,
    indexes: {
      augmentsByApiName: buildAugmentIndex(augments),
      itemsByApiName: buildItemIndex(items),
      championsByApiName: Object.fromEntries(champions.map((champion) => [champion.apiName, champion])),
      compsBySlug: Object.fromEntries(comps.map((comp) => [comp.slug, comp])),
    },
  };

  writeJson(path.join(OUT_DIR, "latest.json"), snapshot);
  writeJson(path.join(OUT_DIR, `snapshot-${fetchedAt.replace(/[:.]/g, "-")}.json`), snapshot);
  console.log(`Wrote ${path.join(OUT_DIR, "latest.json")}`);
  console.log(`Augments: ${augments.length} records, items: ${items.length} records, champions: ${champions.length}, comps: ${comps.length} comps`);
  console.log(`Champion icons: ${championIconCount} downloaded or already present`);
  console.log(`Item icons: ${itemIconCount} downloaded or already present`);
  console.log(`Trait icons: ${traitIconCount} downloaded or already present`);
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
          displayName: cleanAugmentDisplayName(augmentNamesByApiName[apiName] || displayNameFromApiName(apiName), apiName),
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
    index[record.apiName] = cleanAugmentDisplayName(record.name, record.apiName);
  }
  return index;
}

function cleanAugmentDisplayName(name, apiName) {
  let result = String(name || "");
  if (apiName === "TFT_Augment_GainGold") {
    result = result.replace(/@Gold@/g, "21");
  }
  return result;
}

function buildChampionInfoIndex(staticData) {
  const index = {};
  for (const set of staticData.setData || []) {
    for (const champion of set.champions || []) {
      if (!champion || !champion.apiName) {
        continue;
      }
      const icon = champion.icon || "";
      index[champion.apiName] = {
        apiName: champion.apiName,
        name: champion.name || displayNameFromApiName(champion.apiName),
        cost: champion.cost,
        traits: champion.traits || [],
        icon,
        fallbackIconUrl: communityDragonGameAssetUrl(icon),
      };
    }
  }
  return index;
}

function buildTraitInfoIndex(staticData, setNumber) {
  const index = {};
  const currentSetPrefix = `TFT${setNumber}_`;
  for (const set of staticData.setData || []) {
    for (const trait of set.traits || []) {
      if (!trait || !trait.apiName) {
        continue;
      }
      const icon = trait.icon || "";
      const info = {
        apiName: trait.apiName,
        name: trait.name || displayNameFromApiName(trait.apiName),
        icon,
        fallbackIconUrl: communityDragonGameAssetUrl(icon),
      };
      index[trait.apiName] = info;

      const isCurrentSetTrait = trait.apiName.startsWith(currentSetPrefix) || icon.toLowerCase().includes(`trait_icon_${setNumber}`);
      if (isCurrentSetTrait && info.name) {
        index[info.name] = info;
        index[normalizeName(info.name)] = info;
      }
    }
  }
  return index;
}

function buildItemInfoIndex(staticData) {
  const index = {};
  const records = [];
  records.push(...(staticData.items || []));
  for (const set of staticData.setData || []) {
    records.push(...(set.items || []));
  }
  for (const item of records) {
    if (!item || !item.apiName) {
      continue;
    }
    const icon = item.icon || "";
    index[item.apiName] = {
      apiName: item.apiName,
      name: item.name || displayNameFromApiName(item.apiName),
      icon,
      fallbackIconUrl: communityDragonGameAssetUrl(icon),
    };
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

function normalizeItems(records, itemInfoByApiName) {
  const normalized = [];
  for (const record of records) {
    for (const [tier, apiNames] of Object.entries(record.tier || {})) {
      for (const apiName of apiNames || []) {
        const info = itemInfoByApiName[apiName] || {};
        normalized.push({
          apiName,
          name: info.name || displayNameFromApiName(apiName),
          tier,
          type: record.type,
          set: record.set,
          updated: record.updated,
          icon: info.icon || "",
          fallbackIconUrl: info.fallbackIconUrl || "",
          localIconPath: path.join("items", `${apiName}.png`),
        });
      }
    }
  }
  return normalized.sort((a, b) => `${a.type}:${a.tier}:${a.apiName}`.localeCompare(`${b.type}:${b.tier}:${b.apiName}`));
}

function normalizeChampions(championInfoByApiName, setNumber) {
  const currentSetPrefix = `TFT${setNumber}_`;
  return Object.values(championInfoByApiName)
    .filter((champion) =>
      champion.apiName &&
      champion.apiName.startsWith(currentSetPrefix) &&
      !isNonRosterChampionApiName(champion.apiName) &&
      champion.name &&
      Array.isArray(champion.traits) &&
      champion.traits.length > 0
    )
    .map((champion) => ({
      ...champion,
      iconUrl: tftAcademyChampionIconUrl(champion.apiName),
      localIconPath: path.join("champions", `${champion.apiName}.webp`),
    }))
    .sort((a, b) => (a.cost ?? 99) - (b.cost ?? 99) || a.name.localeCompare(b.name));
}

function isNonRosterChampionApiName(apiName) {
  return /(?:FakeUnit|_Summon$|_Relic$)/i.test(String(apiName || ""));
}

function normalizeComps(guides, championInfoByApiName, traitInfoByApiName, itemInfoByApiName) {
  return guides.map((guide) => {
    const finalComp = enrichCompUnits(guide.finalComp || [], championInfoByApiName);
    return {
      id: guide.id,
      slug: guide.compSlug || "",
      title: guide.title || guide.metaTitle || "",
      metaTitle: guide.metaTitle || "",
      tier: guide.tier || "",
      style: guide.style || "",
      difficulty: guide.difficulty || "",
      mainChampion: enrichChampion(guide.mainChampion, championInfoByApiName),
      mainAugment: guide.mainAugment || null,
      augmentTypes: guide.augmentTypes || [],
      augments: apiNames(guide.augments),
      overlayAugments: apiNames(guide.overlayAugments),
      godBoons: normalizeGodBoons(guide),
      carousel: enrichItems(guide.carousel || [], itemInfoByApiName),
      traits: normalizeTraits(guide.traits || guide.activeTraits || guide.traitList || [], traitInfoByApiName, finalComp),
      finalComp,
      earlyComp: enrichCompUnits(guide.earlyComp || [], championInfoByApiName),
      tips: guide.tips || [],
      updated: guide.updated || null,
    };
  }).sort((a, b) => tierRank(a.tier) - tierRank(b.tier) || a.title.localeCompare(b.title));
}

function normalizeGodBoons(guide) {
  const candidates = [
    guide.godBoons,
    guide.god_boons,
    guide.gods,
    guide.god,
    guide.powerups,
    guide.powerUps,
    guide.powerup,
    guide.recommendedGods,
    guide.recommended_gods,
  ];
  const boons = [];
  for (const candidate of candidates) {
    collectGodBoons(candidate, boons);
  }
  const seen = new Set();
  return boons.filter((boon) => {
    const key = normalizeName(boon.apiName || boon.displayName);
    if (!key || seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

function collectGodBoons(value, out) {
  if (value == null) {
    return;
  }
  if (typeof value === "string") {
    out.push({ apiName: value, displayName: displayNameFromApiName(value) });
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      collectGodBoons(item, out);
    }
    return;
  }
  if (typeof value !== "object") {
    return;
  }
  const apiName = value.apiName || value.api_name || value.contentId || value.content_id || value.id || value.slug || value.name || value.title;
  const displayName = value.displayName || value.display_name || value.name || value.title || value.label || displayNameFromApiName(apiName);
  if (apiName || displayName) {
    out.push({
      apiName: String(apiName || displayName),
      displayName: String(displayName || apiName),
    });
  }
}

function enrichCompUnits(units, championInfoByApiName) {
  return (units || []).map((unit) => {
    if (!unit || !unit.apiName) {
      return unit;
    }
    const info = championInfoByApiName[unit.apiName] || {};
    const stars = Number(unit.stars ?? unit.starLevel ?? unit.star_level ?? 1);
    return {
      ...unit,
      name: unit.name || info.name || displayNameFromApiName(unit.apiName),
      cost: unit.cost ?? info.cost ?? null,
      items: Array.isArray(unit.items) ? unit.items.filter(Boolean) : [],
      stars: Number.isFinite(stars) && stars > 0 ? stars : 1,
      traits: unit.traits || info.traits || [],
      iconUrl: unit.iconUrl || tftAcademyChampionIconUrl(unit.apiName),
      fallbackIconUrl: info.fallbackIconUrl || "",
      localIconPath: path.join("champions", `${unit.apiName}.webp`),
    };
  });
}

function enrichChampion(champion, championInfoByApiName) {
  if (!champion || !champion.apiName) {
    return champion || null;
  }
  const info = championInfoByApiName[champion.apiName] || {};
  const iconUrl = champion.iconUrl || tftAcademyChampionIconUrl(champion.apiName);
  return {
    ...champion,
    name: champion.name || info.name || displayNameFromApiName(champion.apiName),
    cost: champion.cost ?? info.cost ?? null,
    traits: champion.traits || info.traits || [],
    icon: champion.icon || info.icon || "",
    iconUrl,
    fallbackIconUrl: info.fallbackIconUrl || "",
    localIconPath: path.join("champions", `${champion.apiName}.webp`),
  };
}

function enrichItems(items, itemInfoByApiName) {
  return (items || []).map((value) => {
    const apiName = value && typeof value === "object" ? value.apiName : value;
    const info = itemInfoByApiName[apiName] || {};
    return {
      ...(value && typeof value === "object" ? value : {}),
      apiName,
      name: info.name || displayNameFromApiName(apiName),
      icon: info.icon || "",
      fallbackIconUrl: info.fallbackIconUrl || "",
      localIconPath: path.join("items", `${apiName}.png`),
    };
  }).filter((item) => item.apiName);
}

function normalizeTraits(rawTraits, traitInfoByApiName, finalComp) {
  const direct = (rawTraits || []).map((value) => {
    const rawApiName = value && typeof value === "object" ? (value.apiName || value.trait || value.id || value.name) : value;
    if (!rawApiName) {
      return null;
    }
    const info = traitInfoByApiName[rawApiName] || traitInfoByApiName[normalizeName(rawApiName)] || {};
    const apiName = info.apiName || rawApiName;
    const name = value.name || info.name || displayNameFromApiName(rawApiName);
    return {
      apiName,
      name,
      count: Number(value.count || value.value || value.numUnits || 0),
      icon: info.icon || "",
      fallbackIconUrl: info.fallbackIconUrl || "",
      localIconPath: path.join("traits", `${apiName}.png`),
    };
  }).filter(Boolean);
  if (direct.length > 0) {
    return direct;
  }

  const counts = new Map();
  for (const unit of finalComp || []) {
    for (const trait of unit.traits || []) {
      counts.set(trait, (counts.get(trait) || 0) + 1);
    }
  }
  return [...counts.entries()]
    .map(([apiName, count]) => {
      const info = traitInfoByApiName[apiName] || traitInfoByApiName[normalizeName(apiName)] || {};
      const canonicalApiName = info.apiName || apiName;
      return {
        apiName: canonicalApiName,
        name: info.name || displayNameFromApiName(apiName),
        count,
        icon: info.icon || "",
        fallbackIconUrl: info.fallbackIconUrl || "",
        localIconPath: path.join("traits", `${canonicalApiName}.png`),
      };
    })
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}

async function downloadChampionIcons(comps, outDir) {
  const championsDir = path.join(outDir, "champions");
  fs.mkdirSync(championsDir, { recursive: true });

  const champions = new Map();
  for (const comp of comps) {
    for (const champion of [comp.mainChampion, ...(comp.finalComp || []), ...(comp.earlyComp || [])]) {
      if (champion && champion.apiName) {
        champions.set(champion.apiName, [
          { url: champion.iconUrl || tftAcademyChampionIconUrl(champion.apiName), extension: "webp" },
          { url: champion.fallbackIconUrl || "", extension: "png" },
        ].filter((candidate) => candidate.url));
      }
    }
  }

  let count = 0;
  for (const [apiName, candidates] of champions) {
    const existing = ["webp", "png", "jpg", "jpeg"].some((extension) => fs.existsSync(path.join(championsDir, `${apiName}.${extension}`)));
    if (existing) {
      count += 1;
      continue;
    }

    let downloaded = false;
    for (const candidate of candidates) {
      try {
        const response = await fetch(candidate.url, { headers: { "user-agent": "TFTOverlay/0.1 local development scraper" } });
        if (!response.ok) {
          continue;
        }
        const bytes = Buffer.from(await response.arrayBuffer());
        fs.writeFileSync(path.join(championsDir, `${apiName}.${candidate.extension}`), bytes);
        count += 1;
        downloaded = true;
        break;
      } catch (error) {
        console.warn(`Could not download champion icon for ${apiName} from ${candidate.url}: ${error.message}`);
      }
    }
    if (!downloaded) {
      console.warn(`Could not download champion icon for ${apiName}`);
    }
  }
  return count;
}

async function downloadItemIcons(items, comps, outDir) {
  const itemsDir = path.join(outDir, "items");
  fs.mkdirSync(itemsDir, { recursive: true });

  const itemMap = new Map();
  for (const item of items || []) {
    if (item && item.apiName) {
      itemMap.set(item.apiName, [{ url: item.fallbackIconUrl || "", extension: "png" }].filter((candidate) => candidate.url));
    }
  }
  for (const comp of comps || []) {
    for (const item of comp.carousel || []) {
      if (item && item.apiName && !itemMap.has(item.apiName)) {
        itemMap.set(item.apiName, [{ url: item.fallbackIconUrl || "", extension: "png" }].filter((candidate) => candidate.url));
      }
    }
    for (const unit of [...(comp.finalComp || []), ...(comp.earlyComp || [])]) {
      for (const itemApiName of unit.items || []) {
        if (itemApiName && !itemMap.has(itemApiName)) {
          const fallback = `${ASSETS_BASE_URL}/items/${itemApiName}.webp`;
          itemMap.set(itemApiName, [{ url: fallback, extension: "webp" }]);
        }
      }
    }
  }
  return await downloadIconMap(itemMap, itemsDir);
}

async function downloadTraitIcons(comps, outDir) {
  const traitsDir = path.join(outDir, "traits");
  fs.mkdirSync(traitsDir, { recursive: true });

  const traitMap = new Map();
  for (const comp of comps || []) {
    for (const trait of comp.traits || []) {
      if (trait && trait.apiName) {
        traitMap.set(trait.apiName, [{ url: trait.fallbackIconUrl || "", extension: "png" }].filter((candidate) => candidate.url));
      }
    }
  }
  return await downloadIconMap(traitMap, traitsDir);
}

async function downloadIconMap(iconMap, outDir) {
  let count = 0;
  for (const [apiName, candidates] of iconMap) {
    const existing = ["webp", "png", "jpg", "jpeg"].some((extension) => fs.existsSync(path.join(outDir, `${apiName}.${extension}`)));
    if (existing) {
      count += 1;
      continue;
    }
    let downloaded = false;
    for (const candidate of candidates) {
      try {
        const response = await fetch(candidate.url, { headers: { "user-agent": "TFTOverlay/0.1 local development scraper" } });
        if (!response.ok) {
          continue;
        }
        const bytes = Buffer.from(await response.arrayBuffer());
        fs.writeFileSync(path.join(outDir, `${apiName}.${candidate.extension}`), bytes);
        count += 1;
        downloaded = true;
        break;
      } catch (error) {
        console.warn(`Could not download icon for ${apiName} from ${candidate.url}: ${error.message}`);
      }
    }
    if (!downloaded && candidates.length > 0) {
      console.warn(`Could not download icon for ${apiName}`);
    }
  }
  return count;
}

function tftAcademyChampionIconUrl(apiName) {
  return `${ASSETS_BASE_URL}/champions/champion_icons/${apiName}.webp`;
}

function communityDragonGameAssetUrl(assetPath) {
  if (!assetPath) {
    return "";
  }
  const normalized = String(assetPath)
    .replace(/^\/?lol-game-data\/assets\//i, "")
    .replace(/^\/?game\//i, "")
    .replace(/\.dds$/i, ".png")
    .replace(/\.tex$/i, ".png")
    .toLowerCase();
  return `https://raw.communitydragon.org/latest/game/${normalized}`;
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

function normalizeName(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

function compareAugments(a, b) {
  return `${a.stage}:${a.augmentTier}:${tierRank(a.tier)}:${a.apiName}`.localeCompare(`${b.stage}:${b.augmentTier}:${tierRank(b.tier)}:${b.apiName}`);
}

function tierRank(tier) {
  return { X: 0, S: 1, A: 2, B: 3, C: 4, D: 5 }[tier] ?? 99;
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
