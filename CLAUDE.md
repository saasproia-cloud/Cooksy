APP CONTEXT:

This project is a premium mobile application that transforms short-form cooking videos (TikTok, Instagram, etc.) into clean, structured, and fully usable recipes.

The goal is to provide users with a high-quality cooking experience similar to top apps like Recime, but more reliable and easier to follow.

Users must be able to cook the recipe successfully WITHOUT watching the original video.

The app focuses on:

* clarity
* simplicity
* usability
* premium UX

---

CORE PRINCIPLE:

The system does not "summarize" recipes.

It RECONSTRUCTS them into a complete, structured, and usable format.

---

CRITICAL RULES:

The system MUST ALWAYS output a COMPLETE, COOKABLE recipe.

A recipe is considered COMPLETE ONLY IF it includes:

* a clear dish name
* a full ingredient list (never empty)
* a structured step-by-step instruction list (minimum 6–12 steps depending on dish complexity)
* detailed nutrition data (calories, protein, carbs, fats)

The recipe must be executable without the original video.

---

FAILURE CONDITIONS:

The system MUST NEVER:

* return partial recipes
* return vague ingredients
* return fewer than 5–6 steps
* leave nutrition empty
* copy raw TikTok text
* generate incoherent steps
* forget ingredients
* reference missing ingredients

---

RECONSTRUCTION LOGIC:

1. Detect dish name (MANDATORY)

2. Extract ingredients if available

3. Extract instructions (ALWAYS rewrite and clean)

4. If missing:
   → generate ingredients logically
   → generate full instructions from scratch

5. If no description:
   → infer from video/audio/title
   → generate full recipe

6. If still unclear:
   → return "not_food"

---

INGREDIENT NORMALIZATION:

* remove noise and brand names
* standardize ingredient names
* map synonyms:
  "tomates cerises" → "tomato"
  "blanc de poulet" → "chicken"
  "yaourt grec" → "greek yogurt"

Each ingredient must include:

* quantity
* unit
* clean name

---

INGREDIENT CONSISTENCY (CRITICAL):

* every ingredient must be used at least once
* no step can reference missing ingredients
* no ingredient should be forgotten

---

INSTRUCTION QUALITY:

Each step must:

* describe a clear cooking action
* follow logical order
* be concise (max 2–3 sentences)
* include timing when relevant
* include temperature when needed
* reference ingredients explicitly

Avoid vague or generic steps.

---

COOKING LOGIC VALIDATION:

Before returning:

* ensure no duplicated cooking actions
* ensure correct order (prep → cook → assemble → serve)
* ensure nothing is missing

Fix or regenerate if needed.

---

STEP STRUCTURE:

If needed, group steps:

* Marinade
* Sauce
* Dough
* Assembly

Otherwise keep simple numbered steps.

---

NUTRITION:

Always generate:

* calories
* protein
* carbs
* fats

Use realistic estimation.

---

UX GOAL:

The output must feel like a premium cooking app:

* clean
* structured
* easy to follow
* visually scannable
* no noise
* no inconsistencies

The user must be able to cook successfully using only this recipe.
