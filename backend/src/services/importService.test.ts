import test from "node:test";
import assert from "node:assert/strict";

import { bestSearchQuery } from "./importService.js";
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
