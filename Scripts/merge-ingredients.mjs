#!/usr/bin/env node
// Merge all category JSON files into one clean dataset.
// - Skips core.json (curated subset of other categories).
// - Keeps only entries whose image file actually exists on disk.
// - Deduplicates by image filename (keeps first occurrence).
// - Warns on duplicate French names across categories.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const IMG_DIR = path.join(ROOT, "images ingredients");

const SOURCES = [
  { file: "ingredients.json", folderByCategory: { vegetable: "vegetables", fruit: "fruits" } },
  { file: "sauces.json", folder: "sauces" },
  { file: "spices.json", folder: "spices" },
  { file: "meats.json", folder: "meats" },
  { file: "fish.json", folder: "fish" },
  { file: "dairy.json", folder: "dairy" },
  { file: "grains.json", folder: "grains" },
  { file: "liquids.json", folder: "liquids" },
  { file: "coatings.json", folder: "coatings" },
];

const merged = [];
const seenImages = new Map();
const seenNames = new Map();
const droppedMissing = [];
const droppedDupImage = [];
const warnDupName = [];

for (const src of SOURCES) {
  const jsonPath = path.join(IMG_DIR, src.file);
  const entries = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
  for (const e of entries) {
    const folder = src.folder || src.folderByCategory[e.category];
    if (!folder) {
      console.warn(`Unknown folder for ${e.name} (${e.category})`);
      continue;
    }
    const imgPath = path.join(IMG_DIR, folder, e.image);
    if (!fs.existsSync(imgPath)) {
      droppedMissing.push({ name: e.name, image: e.image, category: e.category });
      continue;
    }
    const imgKey = `${folder}/${e.image}`;
    if (seenImages.has(imgKey)) {
      droppedDupImage.push({
        name: e.name,
        image: e.image,
        category: e.category,
        keptAs: seenImages.get(imgKey),
      });
      continue;
    }
    if (seenNames.has(e.name)) {
      warnDupName.push({ name: e.name, keptAs: seenNames.get(e.name), now: e.category });
    }
    const entry = {
      name: e.name,
      image: `${folder}/${e.image}`,
      category: e.category,
    };
    merged.push(entry);
    seenImages.set(imgKey, entry.name);
    seenNames.set(e.name, entry.category);
  }
}

const outPath = path.join(IMG_DIR, "all-ingredients.json");
fs.writeFileSync(outPath, JSON.stringify(merged, null, 2) + "\n");

console.log("\n───── Merge summary ─────");
console.log(`✓  merged entries:        ${merged.length}`);
console.log(`✗  dropped (no image):    ${droppedMissing.length}`);
console.log(`✗  dropped (dup image):   ${droppedDupImage.length}`);
console.log(`⚠  duplicate names:       ${warnDupName.length}`);

const byCat = {};
for (const e of merged) byCat[e.category] = (byCat[e.category] || 0) + 1;
console.log("\nBy category:");
for (const [c, n] of Object.entries(byCat).sort()) console.log(`  ${c.padEnd(12)} ${n}`);

if (droppedMissing.length) {
  console.log(`\nFirst 10 missing:`);
  for (const d of droppedMissing.slice(0, 10)) console.log(`  - ${d.name} (${d.image})`);
}
if (droppedDupImage.length) {
  console.log(`\nDuplicate images dropped:`);
  for (const d of droppedDupImage) console.log(`  - ${d.name} (${d.image}) — kept as "${d.keptAs}"`);
}
if (warnDupName.length) {
  console.log(`\nDuplicate names (kept first):`);
  for (const d of warnDupName) console.log(`  - ${d.name} — kept in ${d.keptAs}, also seen in ${d.now}`);
}

console.log(`\n✓ wrote ${outPath}`);
