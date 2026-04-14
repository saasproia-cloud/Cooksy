APP CONTEXT:

This project is a premium mobile application that transforms short-form cooking videos (TikTok, Instagram, etc.) into clean, structured, and usable recipes.

The goal is to produce recipes that are:
- clear
- structured
- faithful to the source
- directly usable in real cooking

Users must be able to cook WITHOUT watching the original video.

---

CORE PRINCIPLE:

The system does NOT blindly generate recipes.

It MUST:
→ extract
→ preserve
→ structure
→ complete ONLY when needed

Never degrade high-quality input.

---

CRITICAL RULE:

If the input (caption or audio) already contains a good recipe:
→ DO NOT rewrite it entirely
→ DO NOT simplify it
→ ONLY clean and structure it

---

SOURCE PRIORITY (MANDATORY):

1. Caption (highest priority)
2. Audio (complement only)
3. Inference (last resort)

The system MUST NOT mix sources blindly.

It must preserve the most reliable source.

---

STRUCTURE PRESERVATION (CRITICAL):

If the input contains sections like:
- marinade
- sauce
- salad
- assembly

→ These sections MUST be preserved.

Recipes must support:

Recipe
  Sections[]
    - name
    - ingredients[]
    - optional steps[]

Never flatten structured content.

---

INGREDIENT RULES:

Ingredients must be:

- natural
- precise
- human-readable

NEVER:

- force quantity if unknown
- generate fake units
- produce unnatural formats

Examples:

❌ "30 salade"
❌ "à soupe huile"
❌ "à café paprika"

✅ "salade"
✅ "2 c. à s. d’huile"
✅ "1 c. à c. de paprika"

---

PRECISION RULE (CRITICAL):

NEVER reduce ingredient specificity.

Examples:

❌ "ribeye" → "steak"
❌ "provolone" → "cheese"
❌ "blanc de poulet" → "chicken"

Keep original names whenever possible.

---

GENERATION RULE:

ONLY generate when necessary.

If data is missing:
→ complete logically

If data is already present:
→ preserve it

---

INSTRUCTIONS:

Steps must:

- follow logical cooking order
- reference existing ingredients
- be clear and actionable
- avoid unnecessary verbosity

Do NOT rewrite steps if already clear.

---

CONSISTENCY RULES:

- every important ingredient should be used
- no step can reference a missing ingredient
- no duplication or contradiction

---

VALIDATION (MANDATORY):

Before returning:

- structure is preserved
- ingredients are valid
- no malformed entries
- steps are coherent
- recipe is cookable

If not:
→ fix OR regenerate only the problematic parts

---

NUTRITION:

Generate realistic estimates if possible.

If insufficient data:
→ estimate conservatively

---

FAILURE CASE:

If there is not enough information to identify a dish:
→ return "not_food"

---

FINAL OBJECTIVE:

The system must:

- outperform raw input
- preserve structure
- avoid hallucination
- produce reliable recipes every time

No over-generation.
No degradation.
Only controlled reconstruction.