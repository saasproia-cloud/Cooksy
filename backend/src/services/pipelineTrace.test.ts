import test from "node:test";
import assert from "node:assert/strict";

import {
  createPipelineTrace,
  recordStageDuration,
  summarizeEnvelopes,
  summarizeSnapshot,
} from "./pipelineTrace.js";
import { buildCleanedPrimarySnapshot } from "./pipelineSnapshots.js";
import { buildSourceEnvelopes } from "./sourceSanitizer.js";
import type { RecipeImportResult } from "../types/recipe.js";

function makeRecipe(): RecipeImportResult {
  return {
    title: "Poulet curry",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "1", unit: "", name: "poulet", nutritionQuery: "", group: "" },
    ],
    stepDrafts: [{ detail: "Cuire le poulet", section: "" }],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "medium",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false,
  } as RecipeImportResult;
}

test("createPipelineTrace initializes empty trace", () => {
  const trace = createPipelineTrace("https://example.com/video");
  assert.equal(trace.url, "https://example.com/video");
  assert.ok(trace.requestId.length > 0);
  assert.equal(trace.envelopes.length, 0);
  assert.equal(trace.snapshots.length, 0);
});

test("summarizeEnvelopes extracts trace-relevant fields", () => {
  const envelopes = buildSourceEnvelopes({
    mode: "url",
    socialCaption: "- 200g provolone\n- Ribeye steak",
    socialDescription: "",
    socialPageText: "",
    socialSubtitles: "",
    pageTitle: "",
    pageDescription: "",
    pageTextContent: "",
    pageStructuredData: [],
    transcript: "",
    transcriptDigest: "",
  });
  const summaries = summarizeEnvelopes(envelopes);
  const captionSummary = summaries.find((s) => s.kind === "caption");
  assert.ok(captionSummary);
  assert.ok(captionSummary.rawCharCount > 0);
  assert.ok(captionSummary.recipeLineCount >= 1);
});

test("summarizeSnapshot produces a JSON-safe view", () => {
  const snap = buildCleanedPrimarySnapshot(makeRecipe());
  const view = summarizeSnapshot(snap);
  assert.equal(view.stage, "cleaned_primary");
  assert.equal(view.isBaseline, true);
  assert.equal(view.ingredientCount, 1);
});

test("recordStageDuration appends duration", () => {
  const trace = createPipelineTrace("https://example.com/v");
  recordStageDuration(trace, "stage1", 42);
  assert.equal(trace.stageDurations["stage1"], 42);
});
