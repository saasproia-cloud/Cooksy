#!/usr/bin/env node
// Downloads ingredient photos from TheMealDB into images/ingredients/.
// TheMealDB ingredient images are a curated set of studio shots on clean
// white backgrounds — uniform style, single ingredient, no dishes.
//
// Strategy:
//   - For each entry in images/ingredients.json, derive the English name
//     from the image filename (e.g. "butternut_squash.jpg" -> "Butternut Squash")
//   - Try several naming variants (singular, plural, with/without "es")
//     against https://www.themealdb.com/images/ingredients/{Name}.png
//   - If any variant returns 200 with a non-empty body, save it as .png
//   - If no variant matches, SKIP (option A — strict quality over coverage)
//
// Resumable: files that already exist are skipped.
//
// Usage:
//   node Scripts/fetch-ingredient-images.mjs          # fetch missing
//   node Scripts/fetch-ingredient-images.mjs --force  # overwrite all

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, "..");
const JSON_PATH = path.join(ROOT, "images", "ingredients.json");
const OUT_DIR = path.join(ROOT, "images", "ingredients");
const BASE_URL = "https://www.themealdb.com/images/ingredients";

const FORCE = process.argv.includes("--force");

// Manual overrides for ingredients whose TheMealDB name doesn't match the
// title-cased filename. Discovered by probing the catalog. Keyed by the
// image filename (without extension).
const NAME_OVERRIDES = {
  roma_tomato: "Plum Tomatoes",
  beefsteak_tomato: "Beef Tomatoes",
  baby_potato: "New Potatoes",
  rutabaga: "Swede",
  red_bell_pepper: "Red Pepper",
  green_bell_pepper: "Green Pepper",
  yellow_bell_pepper: "Yellow Pepper",
  chili_pepper: "Chilli",
  corn: "Sweetcorn",
  button_mushroom: "Mushrooms",
  bok_choy: "Pak Choi",
  fava_bean: "Broad Beans",
  arugula: "Rocket",
  flat_bean: "Runner Beans",
  // Fruits
  green_apple: "Bramley Apples",
  red_apple: "Braeburn Apples",
  golden_apple: "Apples",
  plum: "Prunes",
  date: "Medjool Dates",
};

// --- helpers ----------------------------------------------------------------
function titleCaseFromFilename(imageFile) {
  // "butternut_squash.jpg" -> "Butternut Squash"
  return imageFile
    .replace(/\.[a-z]+$/i, "")
    .split("_")
    .map((w) => (w ? w[0].toUpperCase() + w.slice(1) : w))
    .join(" ");
}

function variantsFor(name) {
  // Try several forms because TheMealDB naming is inconsistent
  // (some entries are singular, some plural).
  const out = new Set();
  out.add(name);
  if (name.endsWith("s")) {
    out.add(name.slice(0, -1));
  } else {
    out.add(name + "s");
    if (name.endsWith("o")) out.add(name + "es"); // tomato -> tomatoes
    if (name.endsWith("h")) out.add(name + "es"); // peach -> peaches
    if (/[^aeiou]y$/i.test(name)) {
      out.add(name.slice(0, -1) + "ies"); // strawberry -> strawberries
    }
  }
  return [...out];
}

async function tryDownload(variant) {
  const url = `${BASE_URL}/${encodeURIComponent(variant)}.png`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const buf = Buffer.from(await res.arrayBuffer());
  // TheMealDB returns a ~1 KB placeholder for some missing entries — filter
  // anything suspiciously small.
  if (buf.length < 3000) return null;
  return { buf, url };
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// --- main -------------------------------------------------------------------
const ingredients = JSON.parse(fs.readFileSync(JSON_PATH, "utf8"));
fs.mkdirSync(OUT_DIR, { recursive: true });

const report = { downloaded: [], skipped: [], missing: [], failed: [] };

console.log(`📸 Fetching ${ingredients.length} ingredients from TheMealDB\n`);

for (let i = 0; i < ingredients.length; i++) {
  const ing = ingredients[i];
  // Force .png extension regardless of what's in the JSON.
  const pngName = ing.image.replace(/\.[a-z]+$/i, ".png");
  const dest = path.join(OUT_DIR, pngName);
  const prefix = `[${String(i + 1).padStart(3)}/${ingredients.length}]`;

  if (!FORCE && fs.existsSync(dest)) {
    console.log(`${prefix} ⏭  ${ing.name}  (exists)`);
    report.skipped.push(ing.name);
    continue;
  }

  const stem = ing.image.replace(/\.[a-z]+$/i, "");
  const baseName = NAME_OVERRIDES[stem] || titleCaseFromFilename(ing.image);
  const variants = variantsFor(baseName);

  let found = null;
  let triedUrls = [];
  try {
    for (const v of variants) {
      const r = await tryDownload(v);
      triedUrls.push(v);
      if (r) {
        found = r;
        break;
      }
      await sleep(120);
    }
  } catch (err) {
    console.log(`${prefix} ⚠  ${ing.name}  (${err.message})`);
    report.failed.push({ name: ing.name, error: err.message });
    continue;
  }

  if (!found) {
    console.log(`${prefix} ✗  ${ing.name}  (not in TheMealDB)`);
    report.missing.push({ name: ing.name, tried: triedUrls });
    continue;
  }

  fs.writeFileSync(dest, found.buf);
  console.log(`${prefix} ✓  ${ing.name}  → ${pngName}`);
  report.downloaded.push({ name: ing.name, image: pngName });

  await sleep(150);
}

// --- update ingredients.json to use .png ------------------------------------
const downloadedNames = new Set(report.downloaded.map((d) => d.name));
let jsonChanged = false;
for (const ing of ingredients) {
  if (downloadedNames.has(ing.name) && !ing.image.endsWith(".png")) {
    ing.image = ing.image.replace(/\.[a-z]+$/i, ".png");
    jsonChanged = true;
  }
}
if (jsonChanged) {
  fs.writeFileSync(JSON_PATH, JSON.stringify(ingredients, null, 2) + "\n");
  console.log("\n🔄 Updated ingredients.json to use .png for downloaded entries");
}

// --- summary ---------------------------------------------------------------
console.log("\n───── Summary ─────");
console.log(`✓  downloaded: ${report.downloaded.length}`);
console.log(`⏭  skipped:    ${report.skipped.length}`);
console.log(`✗  not found:  ${report.missing.length}`);
console.log(`⚠  failed:     ${report.failed.length}`);

if (report.missing.length) {
  console.log("\nNot in TheMealDB (skipped):");
  for (const m of report.missing) console.log("  -", m.name);
}
if (report.failed.length) {
  console.log("\nFailed:");
  for (const f of report.failed) console.log(`  - ${f.name}: ${f.error}`);
}
