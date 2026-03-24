import test from "node:test";
import assert from "node:assert/strict";

import { fallbackRecipeFromContext } from "./heuristicRecipeService.js";

test("fallbackRecipeFromContext extracts ingredients and steps from long TikTok captions", () => {
  const caption = [
    "FILET O FISH BURGER #food #recipe #fy #fyp #foryoupage #filet #fish #burger",
    "DOUGH 200 ml milk (lukewarm) 20 g honey 7 g instant yeast (1 tablespoon or 1 packet) 1 egg (medium) 30 ml sunflower oil 20 g butter (unsalted) 425 g flour (all-purpose) 8 g salt (1⅓ teaspoon)",
    "EXTRAS 1 egg (medium) sesame seeds",
    "COD MIXTURE 450 g cod 3 g salt (½ teaspoon) 3 g onion powder (1 teaspoon) 2 g cayenne powder (⅔ teaspoon) 1.5 g black pepper powder (½ teaspoon) 10 g mustard",
    "FLOUR MIXTURE 50 g flour (all-purpose) 50 g cornstarch 3 g salt (½ teaspoon)",
    "--- Instructions Pour the lukewarm milk into a deep bowl. Add honey and yeast, then mix well. Let the mixture rest for 5 minutes. Add sunflower oil, the beaten egg, butter, flour, and salt. Mix and knead the dough for 10-12 minutes until smooth."
  ].join(" ");

  const recipe = fallbackRecipeFromContext({
    mode: "url",
    sourceUrl: "https://www.tiktok.com/@kookmutsjes/video/7448673580990156054",
    socialCaption: caption,
    socialDescription: caption
  });

  assert.equal(recipe.title, "Filet O Fish Burger");
  assert.ok(recipe.ingredientDrafts.length >= 8, `expected >= 8 ingredients, got ${recipe.ingredientDrafts.length}`);
  assert.ok(recipe.stepDrafts.length >= 4, `expected >= 4 steps, got ${recipe.stepDrafts.length}`);
  assert.ok(
    recipe.ingredientDrafts.some((ingredient) => ingredient.name.includes("instant yeast")),
    "expected instant yeast ingredient to be kept intact"
  );
  assert.ok(
    !recipe.ingredientDrafts.some((ingredient) => ingredient.name === "packet)"),
    "did not expect packet fragment to become a standalone ingredient"
  );
  assert.equal(recipe.needsWebFallback, false);
});
