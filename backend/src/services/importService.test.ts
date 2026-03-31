import test from "node:test";
import assert from "node:assert/strict";

import { bestSearchQuery, ensureCookableRecipeStructure, resolveAcceptedRecipeCandidate } from "./importService.js";
import type { RecipeImportResult } from "../types/recipe.js";

function emptyRecipe(overrides: Partial<RecipeImportResult> = {}): RecipeImportResult {
  return {
    title: "",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [],
    stepDrafts: [],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "low",
    needsWebFallback: true,
    searchQuery: "",
    inferredFromPhoto: false,
    ...overrides
  };
}

test("bestSearchQuery builds a dish-focused web query from transcript when TikTok metadata is sparse", () => {
  const query = bestSearchQuery({
    recipe: emptyRecipe(),
    pageSummary: null,
    socialContent: null,
    sharedText: "Regarde cette video TikTok incroyable",
    transcript: "Aujourd'hui on prepare un filet o fish burger maison avec une sauce tartare rapide et du cabillaud pane croustillant."
  });

  assert.match(query.toLowerCase(), /filet o fish|fish burger/);
  assert.match(query.toLowerCase(), /recette/);
});

test("bestSearchQuery prefers an explicit model query when one is already available", () => {
  const query = bestSearchQuery({
    recipe: emptyRecipe({
      searchQuery: "smash burger maison recette"
    }),
    pageSummary: null,
    socialContent: null,
    sharedText: undefined,
    transcript: null
  });

  assert.equal(query, "smash burger maison recette");
});

test("bestSearchQuery ignores social hook titles and falls back to dish cues from subtitles", () => {
  const query = bestSearchQuery({
    recipe: emptyRecipe({
      title: "Réponse à @celia Maintenant vous n'avez plus d'excuses"
    }),
    pageSummary: null,
    socialContent: {
      platform: "tiktok",
      source: "direct",
      canonicalUrl: "https://www.tiktok.com/@demo/video/123",
      title: "Réponse à @celia Maintenant vous n'avez plus d'excuses",
      caption: "Réponse à @celia Maintenant vous n'avez plus d'excuses",
      description: "Réponse à @celia Maintenant vous n'avez plus d'excuses",
      authorName: "cooksy",
      subtitlesText: "Montage burger. Ajouter les hot tenders. Ajouter du coleslaw.",
      imageUrls: [],
      videoUrl: undefined,
      audioUrl: undefined,
      pageText: "Montage burger hot tenders sweet relish coleslaw",
      externalLinks: []
    },
    sharedText: undefined,
    transcript: null
  });

  assert.match(query.toLowerCase(), /burger/);
  assert.match(query.toLowerCase(), /tenders|coleslaw/);
  assert.doesNotMatch(query.toLowerCase(), /excuses|reponse/);
});

test("bestSearchQuery keeps a specific dish phrase when only a flavored dish name is known", () => {
  const query = bestSearchQuery({
    recipe: emptyRecipe({
      title: "Burger a la truffe",
      searchQuery: "Burger a la truffe"
    }),
    pageSummary: null,
    socialContent: null,
    sharedText: "Burger a la truffe",
    transcript: null
  });

  assert.match(query.toLowerCase(), /burger/);
  assert.match(query.toLowerCase(), /truffe|truffle/);
  assert.match(query.toLowerCase(), /recette/);
});

test("bestSearchQuery extracts a crepes query from transcript when the social caption is missing", () => {
  const query = bestSearchQuery({
    recipe: emptyRecipe(),
    pageSummary: null,
    socialContent: null,
    sharedText: "Regarde cette video",
    transcript: "Aujourd'hui on fait des crepes faciles avec farine, lait, oeufs et beurre pour le gouter."
  });

  assert.match(query.toLowerCase(), /crepes|pancakes?/);
  assert.match(query.toLowerCase(), /recette/);
});

test("resolveAcceptedRecipeCandidate keeps a complete AI recipe for dishes not covered by heuristic templates", () => {
  const acceptedRecipe = resolveAcceptedRecipeCandidate(
    emptyRecipe({
      title: "Gyozas au poulet",
      sourceUrl: "https://www.tiktok.com/@cooksy/video/987654321",
      ingredientDrafts: [
        { amount: "24", unit: "pieces", name: "pates a gyozas", nutritionQuery: "gyoza wrappers" },
        { amount: "300", unit: "g", name: "poulet hache", nutritionQuery: "ground chicken" },
        { amount: "2", unit: "", name: "oignons nouveaux", nutritionQuery: "green onion" },
        { amount: "2", unit: "c a soupe", name: "sauce soja", nutritionQuery: "soy sauce" },
        { amount: "1", unit: "c a cafe", name: "gingembre", nutritionQuery: "fresh ginger" },
        { amount: "1", unit: "c a cafe", name: "huile de sesame", nutritionQuery: "sesame oil" }
      ],
      stepDrafts: [
        { detail: "Mélangez le poulet avec les oignons nouveaux, la sauce soja, le gingembre et l'huile de sésame." },
        { detail: "Déposez une petite cuillère de farce au centre de chaque pâte puis repliez les gyozas en scellant bien les bords." },
        { detail: "Faites dorer les gyozas dans une poêle chaude avec un filet d'huile, puis ajoutez un peu d'eau et couvrez pour terminer la cuisson à la vapeur." },
        { detail: "Laissez l'eau s'évaporer, redonnez un peu de croustillant au dessous et servez aussitôt." }
      ],
      confidence: "high",
      needsWebFallback: false,
      searchQuery: "Gyozas au poulet"
    }),
    {
      mode: "url",
      sourceUrl: "https://www.tiktok.com/@cooksy/video/987654321",
      transcript: "Aujourd'hui on fait des gyozas au poulet maison."
    }
  );

  assert.ok(acceptedRecipe, "expected the validated AI recipe to be accepted");
  assert.equal(acceptedRecipe?.title, "Gyozas au poulet");
  assert.ok((acceptedRecipe?.ingredientDrafts.length ?? 0) >= 6);
  assert.ok((acceptedRecipe?.stepDrafts.length ?? 0) >= 4);
  assert.equal(acceptedRecipe?.needsWebFallback, false);
});

test("ensureCookableRecipeStructure expands thin crepes instructions into a cookable set of steps", () => {
  const completedRecipe = ensureCookableRecipeStructure(
    emptyRecipe({
      title: "Crêpes",
      ingredientDrafts: [
        { amount: "250", unit: "g", name: "farine", nutritionQuery: "flour" },
        { amount: "500", unit: "ml", name: "lait", nutritionQuery: "milk" },
        { amount: "4", unit: "", name: "oeufs", nutritionQuery: "egg" },
        { amount: "30", unit: "g", name: "beurre", nutritionQuery: "butter" },
        { amount: "40", unit: "g", name: "sucre", nutritionQuery: "sugar" }
      ],
      stepDrafts: [
        { detail: "Ajoutez le beurre fondu." },
        { detail: "Chauffez une poêle légèrement beurrée." }
      ],
      confidence: "medium",
      needsWebFallback: false,
      searchQuery: "Crêpes recette"
    })
  );

  assert.ok(completedRecipe.stepDrafts.length >= 4);
  assert.equal(
    completedRecipe.stepDrafts.some((step) => /en plusieurs fois|fois en tout|toute petite louche/i.test(step.detail)),
    false
  );
});
