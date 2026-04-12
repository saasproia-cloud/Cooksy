#!/usr/bin/env node
// Copies "images ingredients/default/default.png" into the iOS asset catalog
// so it becomes the fallback image shown when an ingredient has no match.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "images ingredients", "default", "default.png");
const DST_DIR = path.join(
  ROOT,
  "Cooksy",
  "Resources",
  "Assets.xcassets",
  "IngredientIconGeneric.imageset"
);

if (!fs.existsSync(SRC)) {
  console.error(`✗ No image found at: ${SRC}`);
  console.error(`  Drop your fallback photo there as "default.png" first.`);
  process.exit(1);
}

const targets = [
  "IngredientIconGeneric-1x.png",
  "IngredientIconGeneric-2x.png",
  "IngredientIconGeneric-3x.png",
];

for (const name of targets) {
  const dst = path.join(DST_DIR, name);
  fs.copyFileSync(SRC, dst);
  console.log(`✓ ${name}`);
}

console.log(`\n✓ Fallback image applied. Rebuild the app to see it.`);
