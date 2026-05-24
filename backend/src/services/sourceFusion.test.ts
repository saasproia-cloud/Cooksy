// =====================================================================
// sourceFusion — unit tests
//
// These tests lock the §4.3 confidence formula and §4.4 worked example
// from the Round 5 plan. They MUST stay deterministic — no setTimeout,
// no Date.now(), no Math.random(). Any flake here means the formula
// drifted.
// =====================================================================

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  agreementScore,
  computeIngredientConfidence,
  dishCoherenceScore,
  DROP_CONFIDENCE_THRESHOLD,
  fuseIngredientCandidates,
  isProtectedIngredient,
  sourcePriorityScore,
  specificityScore,
  type FusionCandidate
} from "./sourceFusion.js";

// ---------------------------------------------------------------------
// Source-priority term
// ---------------------------------------------------------------------

test("sourcePriorityScore returns the max-priority source value", () => {
  assert.equal(sourcePriorityScore(["caption"]), 1);
  assert.equal(sourcePriorityScore(["description"]), 0.85);
  assert.equal(sourcePriorityScore(["audio"]), 0.65);
  assert.equal(sourcePriorityScore(["hashtag"]), 0.5);
  assert.equal(sourcePriorityScore(["inference"]), 0.3);
  // Max wins when multiple sources contribute.
  assert.equal(sourcePriorityScore(["audio", "caption"]), 1);
  assert.equal(sourcePriorityScore(["inference", "description"]), 0.85);
});

test("sourcePriorityScore returns 0 on empty list", () => {
  assert.equal(sourcePriorityScore([]), 0);
});

// ---------------------------------------------------------------------
// Agreement term
// ---------------------------------------------------------------------

test("agreementScore is 0 for 1 source, 0.6 for 2 sources, 1 for 3+", () => {
  assert.equal(agreementScore(["caption"]), 0);
  assert.equal(agreementScore(["caption", "audio"]), 0.6);
  assert.equal(agreementScore(["caption", "audio", "description"]), 1);
  assert.equal(
    agreementScore(["caption", "audio", "description", "hashtag"]),
    1
  );
});

test("agreementScore counts DISTINCT sources only", () => {
  // 3 caption mentions = 1 distinct source = agreement 0
  assert.equal(agreementScore(["caption", "caption", "caption"]), 0);
  // 2 caption + 1 audio = 2 distinct sources = 0.6
  assert.equal(agreementScore(["caption", "caption", "audio"]), 0.6);
});

// ---------------------------------------------------------------------
// Dish-coherence term
// ---------------------------------------------------------------------

test("dishCoherenceScore returns 1 for signature ingredients of known dish", () => {
  assert.equal(
    dishCoherenceScore({ canonicalName: "farine", dishTitle: "crêpes au sucre" }),
    1
  );
  assert.equal(
    dishCoherenceScore({ canonicalName: "guanciale", dishTitle: "Spaghetti carbonara" }),
    1
  );
});

test("dishCoherenceScore returns 0 for forbidden ingredients in dish", () => {
  // Plan §1: "chou" in "tacos" should be forbidden.
  assert.equal(
    dishCoherenceScore({ canonicalName: "chou", dishTitle: "Tacos au poulet" }),
    0
  );
  // Plan: "creme" in carbonara is forbidden (real carbonara uses egg yolks).
  assert.equal(
    dishCoherenceScore({ canonicalName: "creme", dishTitle: "Carbonara" }),
    0
  );
});

test("dishCoherenceScore returns neutral 0.6 when title absent or no match", () => {
  assert.equal(dishCoherenceScore({ canonicalName: "farine" }), 0.6);
  assert.equal(
    dishCoherenceScore({ canonicalName: "patate douce", dishTitle: "Quelque chose" }),
    0.6
  );
});

// ---------------------------------------------------------------------
// Specificity term
// ---------------------------------------------------------------------

test("specificityScore: generic = 0.3, family = 0.7, specific = 1.0", () => {
  assert.equal(specificityScore("viande"), 0.3);
  assert.equal(specificityScore("fromage"), 0.3);
  assert.equal(specificityScore("poulet"), 0.7);
  assert.equal(specificityScore("ribeye"), 1.0);
  assert.equal(specificityScore("blanc de poulet"), 1.0);
  assert.equal(specificityScore("rigatoni"), 1.0);
});

test("specificityScore defaults to 0.7 for unknown ingredient", () => {
  assert.equal(specificityScore("un truc inconnu"), 0.7);
});

// ---------------------------------------------------------------------
// Combined confidence formula
// ---------------------------------------------------------------------

test("computeIngredientConfidence: a caption-only specific ingredient scores high", () => {
  const c = computeIngredientConfidence({
    sources: ["caption"],
    canonicalName: "ribeye",
    dishTitle: "Cajun ribeye pasta"
  });
  // 0.40*1 + 0.30*0 + 0.20*0.6 + 0.10*1 = 0.62
  assert.equal(c, 0.62);
});

test("computeIngredientConfidence: an inference-only generic ingredient scores low", () => {
  const c = computeIngredientConfidence({
    sources: ["inference"],
    canonicalName: "fromage"
  });
  // 0.40*0.3 + 0.30*0 + 0.20*0.6 + 0.10*0.3 = 0.12 + 0 + 0.12 + 0.03 = 0.27
  assert.equal(c, 0.27);
});

test("computeIngredientConfidence: 2+ sources boost via agreement", () => {
  const c = computeIngredientConfidence({
    sources: ["caption", "audio"],
    canonicalName: "ribeye",
    dishTitle: "Cajun ribeye pasta"
  });
  // 0.40*1 + 0.30*0.6 + 0.20*0.6 + 0.10*1 = 0.40 + 0.18 + 0.12 + 0.10 = 0.80
  assert.equal(c, 0.80);
});

test("computeIngredientConfidence: signature ingredient pushes coherence to 1", () => {
  const c = computeIngredientConfidence({
    sources: ["caption", "audio", "description"],
    canonicalName: "farine",
    dishTitle: "Crêpes au sucre"
  });
  // 0.40*1 + 0.30*1 + 0.20*1 + 0.10*0.7 = 0.40 + 0.30 + 0.20 + 0.07 = 0.97
  assert.equal(c, 0.97);
});

test("computeIngredientConfidence: forbidden in dish drops coherence to 0", () => {
  const c = computeIngredientConfidence({
    sources: ["audio"],
    canonicalName: "chou",
    dishTitle: "Tacos al pastor"
  });
  // 0.40*0.65 + 0.30*0 + 0.20*0 + 0.10*0.7 = 0.26 + 0 + 0 + 0.07 = 0.33
  assert.equal(c, 0.33);
});

test("computeIngredientConfidence is deterministic across calls", () => {
  const args = {
    sources: ["caption", "audio"] as const,
    canonicalName: "blanc de poulet",
    dishTitle: "Wrap au poulet"
  };
  const a = computeIngredientConfidence(args);
  const b = computeIngredientConfidence(args);
  const c = computeIngredientConfidence(args);
  assert.equal(a, b);
  assert.equal(b, c);
});

// ---------------------------------------------------------------------
// PROTECTED_INGREDIENTS guard (CONTRAINTE 3)
// ---------------------------------------------------------------------

test("isProtectedIngredient matches the full CONTRAINTE 3 list", () => {
  assert.equal(isProtectedIngredient("Sel"), true);
  assert.equal(isProtectedIngredient("Poivre noir"), true);
  assert.equal(isProtectedIngredient("Huile d'olive"), true);
  assert.equal(isProtectedIngredient("Huile de tournesol"), true);
  assert.equal(isProtectedIngredient("Garniture salade"), true);
  assert.equal(isProtectedIngredient("Sauce piquante"), true);
  assert.equal(isProtectedIngredient("Topping cookies"), true);
  assert.equal(isProtectedIngredient("Assaisonnement maison"), true);
  assert.equal(isProtectedIngredient("Herbes de Provence"), true);
  assert.equal(isProtectedIngredient("Épices à kebab"), true);
  assert.equal(isProtectedIngredient("Pour servir"), true);
  assert.equal(isProtectedIngredient("Pour la déco"), true);
  assert.equal(isProtectedIngredient("Pour la garniture"), true);
});

test("isProtectedIngredient returns false for non-protected names", () => {
  assert.equal(isProtectedIngredient("Blanc de poulet"), false);
  assert.equal(isProtectedIngredient("Mozzarella"), false);
  assert.equal(isProtectedIngredient("Rigatoni"), false);
  assert.equal(isProtectedIngredient(""), false);
});

// ---------------------------------------------------------------------
// Worked example from plan §4.4 — the canonical fusion case
// ---------------------------------------------------------------------

test("plan §4.4 worked example: caption 2 eggs vs audio+description 4 eggs → 4 eggs", () => {
  const candidates: FusionCandidate[] = [
    {
      source: "caption",
      draft: { name: "Œufs", amount: "2", unit: "", group: undefined, nutritionQuery: "" }
    },
    {
      source: "audio",
      draft: { name: "Œufs", amount: "4", unit: "", group: undefined, nutritionQuery: "" }
    },
    {
      source: "description",
      draft: { name: "Œufs", amount: "4", unit: "", group: undefined, nutritionQuery: "" }
    }
  ];
  const result = fuseIngredientCandidates(candidates, { dishTitle: "Omelette" });
  assert.equal(result.ingredients.length, 1);
  const eggs = result.ingredients[0]!;
  assert.equal(eggs.draft.amount, "4"); // audio+description outweigh caption
  // The plan §4.4 "0.97" figure came from a vote-share formula; our §4.3
  // formula (4 weighted terms) is the authoritative one. Computation:
  //   sources = [caption, audio, description] → 3 distinct → agreement = 1
  //   priority = max(caption, audio, descr) = 1.0
  //   dish_coherence = neutral 0.6 (omelette not in our signature table)
  //   specificity for "oeufs" = default 0.7
  //   raw = 0.40*1 + 0.30*1 + 0.20*0.6 + 0.10*0.7 = 0.89
  assert.equal(eggs.confidence, 0.89);
  assert.deepEqual(eggs.provenance.sort(), [
    "audio",
    "caption",
    "description"
  ]);
});

// ---------------------------------------------------------------------
// Drop guard — inference-only low-confidence ingredients
// ---------------------------------------------------------------------

test("fuseIngredientCandidates drops inference-only low-confidence ingredients", () => {
  // A generic-category ingredient inferred without any source backing it →
  //   specificity = 0.3, agreement = 0, priority = 0.3, coherence = 0.6
  //   raw = 0.40*0.3 + 0.30*0 + 0.20*0.6 + 0.10*0.3 = 0.27 < 0.30 → drop.
  const candidates: FusionCandidate[] = [
    {
      source: "inference",
      draft: { name: "Fromage", amount: "50", unit: "g", group: undefined, nutritionQuery: "" }
    }
  ];
  const result = fuseIngredientCandidates(candidates, {});
  assert.equal(result.ingredients.length, 0);
  assert.equal(result.droppedCount, 1);
});

test("fuseIngredientCandidates NEVER drops protected ingredients, even with low confidence", () => {
  const candidates: FusionCandidate[] = [
    {
      source: "inference",
      draft: { name: "Sel", amount: "", unit: "", group: undefined, nutritionQuery: "" }
    },
    {
      source: "inference",
      draft: { name: "Poivre", amount: "", unit: "", group: undefined, nutritionQuery: "" }
    },
    {
      source: "inference",
      draft: { name: "Huile d'olive", amount: "", unit: "", group: undefined, nutritionQuery: "" }
    },
    {
      source: "inference",
      draft: { name: "Pour servir", amount: "", unit: "", group: undefined, nutritionQuery: "" }
    }
  ];
  const result = fuseIngredientCandidates(candidates, {});
  assert.equal(result.ingredients.length, 4);
  assert.equal(result.droppedCount, 0);
  for (const ing of result.ingredients) {
    assert.equal(ing.isProtected, true);
  }
});

test("fuseIngredientCandidates merges duplicates from different sources via canonical key", () => {
  const candidates: FusionCandidate[] = [
    {
      source: "caption",
      draft: { name: "Œufs", amount: "4", unit: "", group: undefined, nutritionQuery: "" }
    },
    {
      source: "audio",
      draft: { name: "Oeufs", amount: "4", unit: "", group: undefined, nutritionQuery: "" }
    },
    {
      source: "description",
      draft: { name: "eggs", amount: "4", unit: "", group: undefined, nutritionQuery: "" }
    }
  ];
  const result = fuseIngredientCandidates(candidates, {});
  // "Œufs", "Oeufs" → same canonical. "eggs" → different canonical.
  // So we should end up with 2 buckets, not 1.
  assert.equal(result.ingredients.length, 2);
});

test("DROP_CONFIDENCE_THRESHOLD is the public 0.3 boundary", () => {
  // Lock the constant: changing this is a deliberate plan-level decision.
  assert.equal(DROP_CONFIDENCE_THRESHOLD, 0.3);
});

test("fuseIngredientCandidates: caption beats audio when both have same priority signature", () => {
  // Caption says "Steak haché 500 g"; audio says "Steak haché 250 g".
  // Caption weight 0.40 > audio weight 0.26 → 500 g wins.
  const candidates: FusionCandidate[] = [
    {
      source: "caption",
      draft: { name: "Steak haché", amount: "500", unit: "g", group: undefined, nutritionQuery: "" }
    },
    {
      source: "audio",
      draft: { name: "Steak haché", amount: "250", unit: "g", group: undefined, nutritionQuery: "" }
    }
  ];
  const result = fuseIngredientCandidates(candidates, {});
  assert.equal(result.ingredients.length, 1);
  assert.equal(result.ingredients[0]!.draft.amount, "500");
});
