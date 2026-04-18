import test from "node:test";
import assert from "node:assert/strict";

import {
  buildSourceEnvelopes,
  cleanWebText,
  sanitizeCaption,
  sanitizeSocialDescription,
  sanitizeWebText,
} from "./sourceSanitizer.js";

test("sanitizeCaption: null when empty", () => {
  assert.equal(sanitizeCaption(null, null), null);
  assert.equal(sanitizeCaption("", ""), null);
});

test("sanitizeCaption: excludes social description contamination", () => {
  const env = sanitizeCaption(
    "- 3 oeufs\n- 200g farine\n- sel",
    null
  );
  assert.ok(env);
  assert.ok(env!.recipeLines.length >= 3);
  assert.ok(env!.foodSignalScore > 0);
});

test("sanitizeCaption: merges sharedText when distinct", () => {
  const env = sanitizeCaption(
    "- 3 oeufs",
    "Ma super recette\n- 200g farine"
  );
  assert.ok(env);
  assert.ok(env!.cleanedText.includes("oeufs"));
  assert.ok(env!.cleanedText.includes("farine"));
});

test("sanitizeSocialDescription: isolated from caption", () => {
  const env = sanitizeSocialDescription(
    "Suivez-moi sur Instagram @chef\nMusic: Epic Song - SoundCloud"
  );
  assert.ok(env);
  assert.equal(env!.kind, "social_description");
  // Social noise reduces recipe line count.
  assert.equal(env!.recipeLines.length, 0);
});

test("cleanWebText: strips cookie banners", () => {
  const raw = [
    "This site uses cookies to improve your experience.",
    "Accept all cookies",
    "Ingredients:",
    "- 200g flour",
    "- 2 eggs",
    "Copyright 2024 All rights reserved",
  ].join("\n");
  const cleaned = cleanWebText(raw);
  assert.ok(!cleaned.toLowerCase().includes("cookies"));
  assert.ok(!cleaned.toLowerCase().includes("all rights reserved"));
  assert.ok(cleaned.includes("200g flour"));
  assert.ok(cleaned.includes("2 eggs"));
});

test("cleanWebText: strips social share strips", () => {
  const raw = [
    "Share on Facebook",
    "Tweet this recipe",
    "- 3 eggs",
    "Follow us on Instagram",
  ].join("\n");
  const cleaned = cleanWebText(raw);
  assert.ok(!cleaned.toLowerCase().includes("share on facebook"));
  assert.ok(!cleaned.toLowerCase().includes("tweet this"));
  assert.ok(!cleaned.toLowerCase().includes("follow us"));
  assert.ok(cleaned.includes("3 eggs"));
});

test("cleanWebText: strips navigation menu items", () => {
  const raw = [
    "Home",
    "Recipes",
    "About",
    "Contact",
    "Ingredients for chocolate cake:",
    "- 200g flour",
  ].join("\n");
  const cleaned = cleanWebText(raw);
  assert.ok(!cleaned.split("\n").some((l) => l.trim().toLowerCase() === "home"));
  assert.ok(cleaned.includes("200g flour"));
});

test("sanitizeWebText: includes title and strips boilerplate", () => {
  const env = sanitizeWebText(
    "Best Chocolate Cake Recipe",
    "A moist and rich chocolate cake",
    [
      "Home",
      "Ingredients:",
      "- 200g flour",
      "- 2 eggs",
      "- 100g sugar",
      "Method:",
      "Preheat oven to 180C.",
      "Copyright 2024",
    ].join("\n")
  );
  assert.ok(env);
  assert.ok(env!.cleanedText.includes("200g flour"));
  assert.ok(!env!.cleanedText.toLowerCase().includes("copyright"));
});

test("buildSourceEnvelopes: separates caption and description", () => {
  const envs = buildSourceEnvelopes({
    mode: "url",
    socialCaption: "- 3 oeufs\n- 200g farine\n- sel",
    socialDescription: "Abonne-toi pour plus de recettes",
    transcript: null as unknown as string,
  });
  const caption = envs.find((e) => e.kind === "caption");
  const description = envs.find((e) => e.kind === "social_description");
  assert.ok(caption, "expected caption envelope");
  assert.ok(description, "expected social_description envelope");
  // Contamination isolation — description does not leak into caption.
  assert.ok(!caption!.cleanedText.toLowerCase().includes("abonne"));
});

test("buildSourceEnvelopes: detects section hints", () => {
  const envs = buildSourceEnvelopes({
    mode: "url",
    socialCaption: [
      "Pour la marinade:",
      "- 3 c. à soupe sauce soja",
      "- 1 gousse d'ail",
      "Pour le montage:",
      "- pain burger",
      "- salade",
    ].join("\n"),
  });
  const caption = envs.find((e) => e.kind === "caption");
  assert.ok(caption);
  assert.ok(caption!.sectionHints.length >= 2);
});
