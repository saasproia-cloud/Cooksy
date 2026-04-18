import test from "node:test";
import assert from "node:assert/strict";

import {
  __foodTokenSetSize,
  containsFoodSignal,
  foodSignalScore,
  hasPlausibleIngredientShape,
  passesDualGate,
} from "./foodTermGate.js";

// =====================================================================
// Coverage sanity — the allowlist must be non-trivially populated.
// =====================================================================

test("food token set loaded with substantial coverage", () => {
  assert.ok(
    __foodTokenSetSize() >= 200,
    `expected >=200 food tokens, got ${__foodTokenSetSize()}`
  );
});

// =====================================================================
// Gate B — containsFoodSignal
// =====================================================================

test("containsFoodSignal: common FR proteins", () => {
  assert.ok(containsFoodSignal("poulet"));
  assert.ok(containsFoodSignal("blanc de poulet"));
  assert.ok(containsFoodSignal("boeuf haché"));
  assert.ok(containsFoodSignal("ribeye"));
  assert.ok(containsFoodSignal("saumon"));
});

test("containsFoodSignal: specific cheeses", () => {
  assert.ok(containsFoodSignal("provolone"));
  assert.ok(containsFoodSignal("mozzarella di bufala"));
  assert.ok(containsFoodSignal("burrata"));
  assert.ok(containsFoodSignal("feta"));
});

test("containsFoodSignal: international ingredients", () => {
  assert.ok(containsFoodSignal("gochujang"));
  assert.ok(containsFoodSignal("panko"));
  assert.ok(containsFoodSignal("tahini"));
  assert.ok(containsFoodSignal("miso"));
});

test("containsFoodSignal: English common food terms", () => {
  assert.ok(containsFoodSignal("chicken"));
  assert.ok(containsFoodSignal("butter"));
  assert.ok(containsFoodSignal("tomato"));
  assert.ok(containsFoodSignal("olive oil"));
});

test("containsFoodSignal: rejects non-food terms", () => {
  assert.equal(containsFoodSignal("PC"), false);
  assert.equal(containsFoodSignal("Photo editor"), false);
  assert.equal(containsFoodSignal("AI videos for Mac"), false);
  assert.equal(containsFoodSignal("xyz123"), false);
  assert.equal(containsFoodSignal("random nonsense"), false);
});

test("containsFoodSignal: FR compound prefix patterns", () => {
  assert.ok(containsFoodSignal("sauce d'asphodèle"));
  assert.ok(containsFoodSignal("bouillon de volaille"));
  assert.ok(containsFoodSignal("filet de bar"));
});

// =====================================================================
// foodSignalScore — rough density metric
// =====================================================================

test("foodSignalScore: cooking sentence has high score", () => {
  const s = foodSignalScore(
    "Mélangez le beurre, la farine et le sucre dans un bol"
  );
  assert.ok(s > 0.2, `expected > 0.2, got ${s}`);
});

test("foodSignalScore: non-food sentence has zero score", () => {
  assert.equal(foodSignalScore("This is a review of my new laptop"), 0);
});

test("foodSignalScore: empty input returns 0", () => {
  assert.equal(foodSignalScore(""), 0);
  assert.equal(foodSignalScore("   "), 0);
});

// =====================================================================
// Gate A — hasPlausibleIngredientShape
// =====================================================================

test("shape: bullet prefix accepted", () => {
  assert.ok(hasPlausibleIngredientShape("- 200g provolone"));
  assert.ok(hasPlausibleIngredientShape("• Oignon rouge"));
  assert.ok(hasPlausibleIngredientShape("* Beurre"));
  assert.ok(hasPlausibleIngredientShape("1. Poulet"));
});

test("shape: quantity prefix accepted", () => {
  assert.ok(hasPlausibleIngredientShape("200g farine"));
  assert.ok(hasPlausibleIngredientShape("3 oeufs"));
  assert.ok(hasPlausibleIngredientShape("1/2 tasse lait"));
});

test("shape: vulgar fraction prefix accepted", () => {
  assert.ok(hasPlausibleIngredientShape("½ oignon"));
  assert.ok(hasPlausibleIngredientShape("⅓ tasse lait"));
});

test("shape: short plain ingredient line accepted", () => {
  assert.ok(hasPlausibleIngredientShape("Ribeye steak"));
  assert.ok(hasPlausibleIngredientShape("sel"));
  assert.ok(hasPlausibleIngredientShape("oignon"));
  assert.ok(hasPlausibleIngredientShape("Blanc de poulet mariné 30 min"));
});

test("shape: rejects narrative with internal sentence-end", () => {
  assert.equal(
    hasPlausibleIngredientShape("Mélangez le tout. Puis ajoutez le sel."),
    false
  );
});

test("shape: rejects lines starting with imperative cooking verb", () => {
  assert.equal(
    hasPlausibleIngredientShape("Faites revenir les oignons"),
    false
  );
  assert.equal(
    hasPlausibleIngredientShape("Mélangez la farine et le lait"),
    false
  );
  assert.equal(
    hasPlausibleIngredientShape("Preheat the oven to 180°C"),
    false
  );
});

test("shape: rejects article-like titles", () => {
  assert.equal(
    hasPlausibleIngredientShape("The best cheesecake in Paris"),
    false
  );
  assert.equal(
    hasPlausibleIngredientShape("Top 10 recettes de l'été"),
    false
  );
  assert.equal(
    hasPlausibleIngredientShape("Les meilleurs burgers de Paris"),
    false
  );
});

test("shape: rejects product/brand names with 3+ TitleCase tokens", () => {
  assert.equal(
    hasPlausibleIngredientShape("Kiri Studio Pro Edition"),
    false
  );
  assert.equal(
    hasPlausibleIngredientShape("Adobe Photoshop Pro Max"),
    false
  );
});

test("shape: rejects lines with product suffix markers", () => {
  assert.equal(hasPlausibleIngredientShape("Photo Editor Pro"), false);
  assert.equal(hasPlausibleIngredientShape("AI videos for Mac"), false);
  assert.equal(hasPlausibleIngredientShape("Premium edition"), false);
});

test("shape: rejects social CTAs", () => {
  assert.equal(
    hasPlausibleIngredientShape("Abonne-toi pour plus de poulet"),
    false
  );
  assert.equal(
    hasPlausibleIngredientShape("Follow me for more recipes"),
    false
  );
  assert.equal(
    hasPlausibleIngredientShape("Lien en bio pour la recette complète"),
    false
  );
});

test("shape: rejects lines over token budget", () => {
  assert.equal(
    hasPlausibleIngredientShape(
      "Once upon a time there was a chef who loved onion very much"
    ),
    false
  );
});

test("shape: short FR compounds with 'de' allowed (lowercase connector)", () => {
  assert.ok(hasPlausibleIngredientShape("Blanc de poulet"));
  assert.ok(hasPlausibleIngredientShape("Sauce soja"));
  assert.ok(hasPlausibleIngredientShape("Jus de citron"));
});

// =====================================================================
// Dual-gate acceptance table (from plan §4)
// =====================================================================

test("dual-gate: '- 200g provolone' accepted", () => {
  assert.equal(passesDualGate("- 200g provolone"), true);
});

test("dual-gate: 'Ribeye steak' accepted", () => {
  assert.equal(passesDualGate("Ribeye steak"), true);
});

test("dual-gate: 'PC' rejected (no food signal)", () => {
  assert.equal(passesDualGate("PC"), false);
});

test("dual-gate: 'Photo editor' rejected (no food signal)", () => {
  assert.equal(passesDualGate("Photo editor"), false);
});

test("dual-gate: 'Kiri Studio Pro Edition' rejected (product shape)", () => {
  // Note: even though "Kiri" could be a brand cheese, the 3+ TitleCase
  // product-name pattern AND product suffix markers reject Gate A.
  assert.equal(passesDualGate("Kiri Studio Pro Edition"), false);
});

test("dual-gate: 'The best cheesecake in Paris' rejected (article title)", () => {
  assert.equal(passesDualGate("The best cheesecake in Paris"), false);
});

test("dual-gate: 'Blanc de poulet mariné 30 min' accepted", () => {
  assert.equal(passesDualGate("Blanc de poulet mariné 30 min"), true);
});

test("dual-gate: 'Abonne-toi pour plus de poulet' rejected (social CTA)", () => {
  assert.equal(passesDualGate("Abonne-toi pour plus de poulet"), false);
});

// =====================================================================
// Dual-gate: real caption samples that MUST pass.
// =====================================================================

test("dual-gate accepts common real-world caption ingredient lines", () => {
  const accepts = [
    "- 2 œufs",
    "• 500g de boeuf haché",
    "1 oignon rouge",
    "300g de provolone",
    "Sel et poivre",
    "2 c. à soupe d'huile d'olive",
    "Quelques feuilles de basilic frais",
    "Pain hoagie",
    "Fromage râpé",
  ];
  for (const line of accepts) {
    assert.equal(
      passesDualGate(line),
      true,
      `expected "${line}" to pass dual gate`
    );
  }
});

test("dual-gate rejects common contamination patterns", () => {
  const rejects = [
    "PC",
    "Photo editor",
    "AI videos for Mac",
    "Kiri Studio Pro Edition",
    "The best cheesecake in Paris",
    "Top 10 recettes rapides",
    "Abonne-toi pour plus",
    "Link in bio",
    "Follow me for more",
    "Subscribe to the channel",
    "Édité avec Adobe Premiere Pro",
  ];
  for (const line of rejects) {
    assert.equal(
      passesDualGate(line),
      false,
      `expected "${line}" to fail dual gate`
    );
  }
});
