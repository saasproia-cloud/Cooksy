// =====================================================================
// Pipeline regression suite (plan §12).
//
// Each fixture under __fixtures__/pipeline/*.json pairs raw sources
// (caption, transcript, page text, structured data) with quality
// expectations (min ingredient count, required tokens, mode hints, …).
// The test iterates every fixture and verifies the deterministic
// compiler + dual-gate + gap analysis + sanitizer honor the plan's
// non-regression contract without any LLM round-trip.
// =====================================================================

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

import { compileRecipeFromSources, captionTriggersHardPrimary } from "./recipeCompiler.js";
import { analyzeGaps } from "./gapAnalyzer.js";
import { buildSourceEnvelopes } from "./sourceSanitizer.js";
import { containsFoodSignal } from "./foodTermGate.js";
import type { NormalizerInput } from "../types/recipe.js";

// Fixtures live in src/ (JSON not copied to dist by tsc). The test runner
// invokes from the backend/ cwd, so we resolve against that.
const FIXTURE_DIR = path.join(
  process.cwd(),
  "src",
  "services",
  "__fixtures__",
  "pipeline"
);

interface FixtureExpect {
  primarySource?: string;
  minIngredients?: number;
  maxIngredients?: number;
  minSteps?: number;
  minSections?: number;
  mustContainIngredientTokens?: string[];
  mustNotContainIngredientTokens?: string[];
  recommendedMode?: "none" | "preservation" | "full";
  needsTitle?: boolean;
  llmNeeded?: boolean;
  captionHardRuleFired?: boolean;
}

interface Fixture {
  name: string;
  description: string;
  input: NormalizerInput;
  expect: FixtureExpect;
}

function loadFixtures(): Fixture[] {
  const files = fs
    .readdirSync(FIXTURE_DIR)
    .filter((f) => f.endsWith(".json"))
    .sort();
  return files.map((file) => {
    const raw = fs.readFileSync(path.join(FIXTURE_DIR, file), "utf8");
    return JSON.parse(raw) as Fixture;
  });
}

function lowerJoin(tokens: string[]): string {
  return tokens.map((t) => t.toLowerCase()).join(" | ");
}

for (const fixture of loadFixtures()) {
  test(`fixture: ${fixture.name}`, () => {
    const result = compileRecipeFromSources(fixture.input);
    const { recipe } = result;
    const exp = fixture.expect;

    const lowerNames = recipe.ingredientDrafts
      .map((i) => (i.name ?? "").toLowerCase())
      .filter(Boolean);
    const joined = lowerNames.join(" | ");

    if (exp.minIngredients !== undefined) {
      assert.ok(
        recipe.ingredientDrafts.length >= exp.minIngredients,
        `expected ≥${exp.minIngredients} ingredients, got ${recipe.ingredientDrafts.length} [${lowerJoin(lowerNames)}]`
      );
    }
    if (exp.maxIngredients !== undefined) {
      assert.ok(
        recipe.ingredientDrafts.length <= exp.maxIngredients,
        `expected ≤${exp.maxIngredients} ingredients, got ${recipe.ingredientDrafts.length}`
      );
    }
    if (exp.minSteps !== undefined) {
      assert.ok(
        recipe.stepDrafts.length >= exp.minSteps,
        `expected ≥${exp.minSteps} steps, got ${recipe.stepDrafts.length}`
      );
    }
    if (exp.minSections !== undefined) {
      const distinctSections = new Set(
        recipe.ingredientDrafts
          .map((i) => (i.group ?? "").trim())
          .filter(Boolean)
      );
      assert.ok(
        distinctSections.size >= exp.minSections,
        `expected ≥${exp.minSections} sections, got ${distinctSections.size}`
      );
    }
    if (exp.mustContainIngredientTokens?.length) {
      for (const token of exp.mustContainIngredientTokens) {
        assert.ok(
          joined.includes(token.toLowerCase()),
          `ingredient token "${token}" not found in [${joined}]`
        );
      }
    }
    if (exp.mustNotContainIngredientTokens?.length) {
      for (const token of exp.mustNotContainIngredientTokens) {
        assert.ok(
          !joined.includes(token.toLowerCase()),
          `ingredient token "${token}" leaked into [${joined}]`
        );
      }
    }

    // Every surviving ingredient must pass the food gate — core contract.
    for (const ing of recipe.ingredientDrafts) {
      assert.ok(
        containsFoodSignal(ing.name ?? ""),
        `ingredient "${ing.name}" failed food-signal gate`
      );
    }

    if (exp.llmNeeded !== undefined) {
      assert.equal(
        result.llmNeeded,
        exp.llmNeeded,
        `expected llmNeeded=${exp.llmNeeded}, got ${result.llmNeeded}`
      );
    }

    const gapReport = analyzeGaps(recipe);
    if (exp.recommendedMode) {
      assert.equal(
        gapReport.recommendedMode,
        exp.recommendedMode,
        `expected recommendedMode=${exp.recommendedMode}, got ${gapReport.recommendedMode}`
      );
    }
    if (exp.needsTitle !== undefined) {
      assert.equal(
        gapReport.needsTitle,
        exp.needsTitle,
        `expected needsTitle=${exp.needsTitle}, got ${gapReport.needsTitle}`
      );
    }

    if (exp.captionHardRuleFired) {
      const envelopes = buildSourceEnvelopes(fixture.input);
      const captionEnv = envelopes.find((e) => e.kind === "caption");
      assert.ok(captionEnv, "caption envelope expected");
      // The compiler output should originate from the caption path; a
      // caption that satisfies the HARD RULE must end up as primary.
      assert.equal(
        result.primarySource,
        "caption",
        `expected caption-derived primary source, got ${result.primarySource}`
      );
    }

    if (exp.primarySource) {
      assert.equal(
        result.primarySource,
        exp.primarySource,
        `expected primarySource=${exp.primarySource}, got ${result.primarySource}`
      );
    }
  });
}

test("captionTriggersHardPrimary: explicit sections without numbered steps", () => {
  const parsed = {
    title: "Smash burgers",
    sections: [
      { name: "Galettes", ingredients: [{ amount: "500", unit: "g", name: "boeuf", nutritionQuery: "" }], steps: [] },
      { name: "Garniture", ingredients: [{ amount: "4", unit: "", name: "cheddar", nutritionQuery: "" }], steps: [] },
    ],
    rawIngredientCount: 2,
    rawStepCount: 0,
  };
  assert.equal(captionTriggersHardPrimary(parsed as any), true);
});
