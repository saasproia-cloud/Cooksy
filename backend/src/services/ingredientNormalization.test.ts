import test from "node:test";
import assert from "node:assert/strict";

import {
  INGREDIENT_SYNONYM_TABLE,
  assertNoGenerification,
  canonicalizeIngredientKey,
  cleanIngredientNameField,
  normalizeFrenchIngredientName,
  normalizeFrenchUnit,
  stripSocialNoise,
} from "./ingredientNormalization.js";

test("canonicalizeIngredientKey strips accents, oe ligature, punctuation", () => {
  assert.equal(canonicalizeIngredientKey("Œufs"), "oeufs");
  assert.equal(canonicalizeIngredientKey("Crème fraîche"), "creme fraiche");
  assert.equal(canonicalizeIngredientKey("Huile d'olive"), "huile d olive");
});

test("normalizeFrenchIngredientName uses ASCII oe to keep regex compatibility", () => {
  assert.equal(normalizeFrenchIngredientName("oeufs").displayName, "Oeufs");
  assert.equal(normalizeFrenchIngredientName("boeuf hache").displayName, "Boeuf haché");
});

test("synonym table preserves specificity (no bare-category values)", () => {
  // The module's load-time guard should already have run; rerun explicitly
  // for an isolated assertion.
  assert.doesNotThrow(() => assertNoGenerification());
});

test("normalizeFrenchIngredientName normalizes common spoken forms", () => {
  assert.equal(normalizeFrenchIngredientName("oeufs").displayName, "Oeufs");
  assert.equal(
    normalizeFrenchIngredientName("blanc de poulet").displayName,
    "Blanc de poulet"
  );
  assert.equal(
    normalizeFrenchIngredientName("creme fraiche").displayName,
    "Crème fraîche"
  );
});

test("normalizeFrenchIngredientName never collapses specific names", () => {
  // Specific names that must round-trip without being genericized.
  for (const specific of ["provolone", "ribeye", "panko", "gochujang", "guanciale"]) {
    const result = normalizeFrenchIngredientName(specific);
    const lower = result.displayName.toLowerCase();
    assert.ok(
      lower.includes(specific),
      `expected "${specific}" to survive normalization, got "${result.displayName}"`
    );
  }
});

test("normalizeFrenchIngredientName preserves qualified forms", () => {
  for (const qualified of [
    "sauce soja",
    "fromage frais",
    "pain burger",
    "oignon rouge",
    "viande hachee",
  ]) {
    const result = normalizeFrenchIngredientName(qualified);
    assert.ok(
      result.displayName.length > 0,
      `expected qualified form "${qualified}" to keep a non-empty display name`
    );
    // Should never be reduced to a single bare category word.
    assert.ok(
      result.displayName.split(/\s+/).length >= 2 ||
        result.displayName.toLowerCase() === qualified.toLowerCase(),
      `qualified form "${qualified}" was collapsed to "${result.displayName}"`
    );
  }
});

test("normalizeFrenchIngredientName returns raw for unknown inputs", () => {
  const result = normalizeFrenchIngredientName("xyz123");
  assert.equal(result.matchedCatalog, false);
  assert.ok(result.displayName.length > 0);
});

test("normalizeFrenchUnit normalizes spoken French units", () => {
  assert.equal(normalizeFrenchUnit("à café"), "c. à café");
  assert.equal(normalizeFrenchUnit("à soupe"), "c. à soupe");
  assert.equal(normalizeFrenchUnit("gr"), "g");
  assert.equal(normalizeFrenchUnit("ML"), "ml");
});

test("INGREDIENT_SYNONYM_TABLE has entries", () => {
  assert.ok(INGREDIENT_SYNONYM_TABLE.size >= 30);
});

test("cleanIngredientNameField extracts leaked 'à soupe' unit prefix", () => {
  const result = cleanIngredientNameField("à soupe huile", "", "");
  assert.equal(result.name, "Huile");
  assert.equal(result.extractedUnit, "c. à soupe");
});

test("cleanIngredientNameField extracts leaked 'à café' unit prefix", () => {
  const result = cleanIngredientNameField("à café sel", "", "");
  assert.equal(result.name, "Sel");
  assert.equal(result.extractedUnit, "c. à café");
});

test("cleanIngredientNameField extracts compound 'cuillère à soupe de X'", () => {
  const result = cleanIngredientNameField("cuillère à soupe de sucre", "", "");
  assert.equal(result.name, "Sucre");
  assert.equal(result.extractedUnit, "c. à soupe");
});

test("cleanIngredientNameField collapses duplicated head word", () => {
  const result = cleanIngredientNameField("Oeufs Oeufs", "", "");
  assert.equal(result.name, "Œufs");
});

test("cleanIngredientNameField collapses duplicated farine", () => {
  const result = cleanIngredientNameField("farine farine", "g", "");
  assert.equal(result.name, "Farine");
});

test("cleanIngredientNameField pulls '300 g farine' into amount+unit+name", () => {
  const result = cleanIngredientNameField("300 g farine", "", "");
  assert.equal(result.name, "Farine");
  assert.equal(result.extractedUnit, "g");
  assert.equal(result.extractedAmount, "300");
});

test("cleanIngredientNameField drops bare unit-only names", () => {
  const result = cleanIngredientNameField("pincée", "", "");
  assert.equal(result.dropped, true);
});

test("cleanIngredientNameField normalizes 'oeufs' head to 'œufs'", () => {
  const result = cleanIngredientNameField("oeufs", "", "");
  assert.equal(result.name, "Œufs");
});

test("cleanIngredientNameField leaves clean input untouched", () => {
  const result = cleanIngredientNameField("Blanc de poulet", "", "");
  assert.equal(result.name, "Blanc de poulet");
  assert.equal(result.extractedUnit, undefined);
});

test("stripSocialNoise removes hashtags at end of line", () => {
  const input = "Faites revenir les oignons #cooking #tiktok";
  const output = stripSocialNoise(input);
  assert.ok(!output.includes("#cooking"));
  assert.ok(output.includes("Faites revenir les oignons"));
});

test("stripSocialNoise removes whole-line CTAs", () => {
  const input = [
    "Mélangez la farine avec le lait.",
    "abonne-toi pour plus de recettes",
    "Cuisez 10 minutes.",
  ].join("\n");
  const output = stripSocialNoise(input);
  assert.ok(!output.toLowerCase().includes("abonne-toi"));
  assert.ok(output.includes("Mélangez la farine"));
  assert.ok(output.includes("Cuisez 10 minutes"));
});

test("stripSocialNoise never removes real cooking content", () => {
  const cheesesteak = [
    "Émincez 400 g de ribeye très finement.",
    "Faites fondre du provolone sur les oignons caramélisés.",
    "Garnissez le pain hoagie avec la viande, les oignons et le fromage.",
    "Servez immédiatement.",
  ].join("\n");
  const output = stripSocialNoise(cheesesteak);
  for (const word of ["ribeye", "provolone", "hoagie", "oignons", "viande", "fromage"]) {
    assert.ok(
      output.toLowerCase().includes(word),
      `cooking word "${word}" was unexpectedly stripped`
    );
  }
});
