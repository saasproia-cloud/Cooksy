#!/usr/bin/env node
// Downloads missing fruit images from Spoonacular CDN
// Only downloads fruits that don't already have a .png in images/ingredients/

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT_DIR = path.join(ROOT, "images", "ingredients");
const BASE = "https://img.spoonacular.com/ingredients_500x500";

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// Map: local filename (without ext) → Spoonacular CDN filename
const SPOONACULAR_MAP = {
  williams_pear: "pear.jpg",
  nashi_pear: "asian-pear.jpg",
  quince: "quince.jpg",
  loquat: "loquats.jpg",
  plantain: "plantains.jpg",
  blood_orange: "blood-orange.jpg",
  grapefruit: "grapefruit.jpg",
  kumquat: "kumquat.jpg",
  bergamot: "bergamot.jpg",
  gooseberry: "gooseberries.jpg",
  lingonberry: "lingonberries.jpg",
  elderberry: "elderberries.jpg",
  goji_berry: "goji-berries.jpg",
  acai_berry: "acai.jpg",
  nectarine: "nectarines.jpg",
  white_grape: "white-grapes.jpg",
  red_grape: "red-grapes.jpg",
  black_grape: "black-grapes.jpg",
  mango: "mango.jpg",
  green_mango: "green-mango.jpg",
  passion_fruit: "passion-fruit.jpg",
  guava: "guava.jpg",
  lychee: "lychees.jpg",
  rambutan: "rambutan.jpg",
  mangosteen: "mangosteen.jpg",
  durian: "durian.jpg",
  jackfruit: "jackfruit.jpg",
  red_dragon_fruit: "dragon-fruit.jpg",
  persimmon: "persimmon.jpg",
  physalis: "physalis.jpg",
  star_fruit: "starfruit.jpg",
  tamarillo: "tamarillo.jpg",
  cherimoya: "custard-apple.jpg",
  sapote: "sapote.jpg",
  feijoa: "feijoa.jpg",
  tamarind: "tamarind.jpg",
  watermelon: "watermelon.jpg",
  charentais_melon: "cantaloupe.jpg",
  green_melon: "honeydew-melon.jpg",
  cantaloupe: "cantaloupe.jpg",
  honeydew_melon: "honeydew-melon.jpg",
  coconut: "coconut.jpg",
};

const report = { downloaded: 0, skipped: 0 };
const entries = Object.entries(SPOONACULAR_MAP);

console.log(`🍎 Downloading ${entries.length} fruits from Spoonacular CDN\n`);

for (let i = 0; i < entries.length; i++) {
  const [localName, cdnFile] = entries[i];
  const dest = path.join(OUT_DIR, localName + ".png");
  const prefix = `[${String(i + 1).padStart(2)}/${entries.length}]`;

  if (fs.existsSync(dest)) {
    console.log(`${prefix} ⏭  ${localName}  (exists)`);
    report.skipped++;
    continue;
  }

  const url = `${BASE}/${cdnFile}`;
  try {
    const res = await fetch(url);
    if (!res.ok) { console.log(`${prefix} ✗  ${localName}  (HTTP ${res.status})`); continue; }
    const buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(dest, buf);
    console.log(`${prefix} ✓  ${localName}  → ${localName}.png (${(buf.length/1024).toFixed(0)} KB)`);
    report.downloaded++;
  } catch (err) {
    console.log(`${prefix} ⚠  ${localName}  (${err.message})`);
  }
  await sleep(120);
}

console.log(`\n✓ downloaded: ${report.downloaded}`);
console.log(`⏭ skipped: ${report.skipped}`);
