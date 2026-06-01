import { z } from "zod";

/**
 * Shared Zod schemas for the Premium chat assistant. These mirror the
 * Swift `ChatMessage` / `ChatSuggestion` / `PendingModification` models
 * exactly. Both sides of the wire validate against these shapes.
 */

// ---------------------------------------------------------------------------
// Suggestion buttons (returned by the assistant when the user asks for a
// modification — e.g. "remplace la sauce soja").
// ---------------------------------------------------------------------------
export const SuggestionOptionSchema = z.object({
  id: z.string().min(1).max(64),
  label: z.string().min(1).max(60),
  shortImpact: z.string().min(1).max(160)
});
export type SuggestionOption = z.infer<typeof SuggestionOptionSchema>;

export const SuggestionTargetSchema = z.object({
  ingredientId: z.string().uuid().optional(),
  ingredientName: z.string().max(120).optional(),
  stepId: z.string().uuid().optional()
});
export type SuggestionTarget = z.infer<typeof SuggestionTargetSchema>;

export const SuggestionGroupSchema = z.object({
  kind: z.enum(["ingredient_swap", "scale_portions"]),
  target: SuggestionTargetSchema.optional(),
  options: z.array(SuggestionOptionSchema).min(1).max(5)
});
export type SuggestionGroup = z.infer<typeof SuggestionGroupSchema>;

// ---------------------------------------------------------------------------
// Pending modification — the structured diff the bot proposes after the
// user picks one of the suggestion buttons. NEVER applied automatically;
// the iOS client must call /api/chat/apply to commit.
// ---------------------------------------------------------------------------
export const IngredientPatchSchema = z.object({
  name: z.string().min(1).max(160),
  amount: z.string().max(60).nullable().optional(),
  unit: z.string().max(40).nullable().optional()
});
export type IngredientPatch = z.infer<typeof IngredientPatchSchema>;

export const StepRewriteSchema = z.object({
  stepId: z.string().uuid(),
  beforeDetail: z.string().min(1),
  afterDetail: z.string().min(1)
});
export type StepRewrite = z.infer<typeof StepRewriteSchema>;

export const NutritionPatchSchema = z.object({
  calories: z.string().nullable().optional(),
  protein: z.string().nullable().optional(),
  carbs: z.string().nullable().optional(),
  fat: z.string().nullable().optional(),
  fiber: z.string().nullable().optional(),
  sugar: z.string().nullable().optional(),
  salt: z.string().nullable().optional(),
  saturatedFat: z.string().nullable().optional()
});
export type NutritionPatch = z.infer<typeof NutritionPatchSchema>;

export const IngredientSwapDiffSchema = z.object({
  kind: z.literal("ingredient_swap"),
  ingredientId: z.string().uuid(),
  before: IngredientPatchSchema,
  after: IngredientPatchSchema,
  stepRewrites: z.array(StepRewriteSchema).max(20).default([]),
  nutritionBefore: NutritionPatchSchema.nullable().optional(),
  nutritionAfter: NutritionPatchSchema.nullable().optional(),
  allergensBefore: z.array(z.string().max(40)).nullable().optional(),
  allergensAfter: z.array(z.string().max(40)).nullable().optional()
});
export type IngredientSwapDiff = z.infer<typeof IngredientSwapDiffSchema>;

export const ScalePortionsDiffSchema = z.object({
  kind: z.literal("scale_portions"),
  factor: z.number().positive().max(20),
  before: z.object({ servings: z.string().nullable().optional() }),
  after: z.object({ servings: z.string().nullable().optional() }),
  ingredientPatches: z.array(
    z.object({
      ingredientId: z.string().uuid(),
      before: IngredientPatchSchema,
      after: IngredientPatchSchema
    })
  ).max(60).default([])
});
export type ScalePortionsDiff = z.infer<typeof ScalePortionsDiffSchema>;

// AddComponents — "ajoute une sauce maison", "ajoute un accompagnement",
// "rajoute une étape". The diff carries the ingredients + step(s) the
// assistant proposes. Apply = push the items onto the recipe lists.
// Revert = remove items whose ids match.
export const AddedIngredientSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1).max(160),
  amount: z.string().max(60).nullable().optional(),
  unit: z.string().max(40).nullable().optional()
});

export const AddedStepSchema = z.object({
  id: z.string().uuid(),
  title: z.string().max(160).nullable().optional(),
  detail: z.string().min(1).max(1_500)
});

export const AddComponentsDiffSchema = z.object({
  kind: z.literal("add_components"),
  // Short label used by the UI ("Sauce maison", "Accompagnement riz",
  // "Garniture", etc.). Surfaces in the assistant card + audit row.
  label: z.string().min(1).max(80),
  addedIngredients: z.array(AddedIngredientSchema).max(15).default([]),
  addedSteps: z.array(AddedStepSchema).max(5).default([]),
  // Nutritional delta applied additively on top of current nutrition.
  nutritionDelta: NutritionPatchSchema.nullable().optional(),
  // Allergens introduced by the addition (e.g. mayonnaise → "œuf").
  allergensAdded: z.array(z.string().max(40)).max(20).default([])
});
export type AddComponentsDiff = z.infer<typeof AddComponentsDiffSchema>;

export const RecipeDiffSchema = z.discriminatedUnion("kind", [
  IngredientSwapDiffSchema,
  ScalePortionsDiffSchema,
  AddComponentsDiffSchema
]);
export type RecipeDiff = z.infer<typeof RecipeDiffSchema>;

export const PendingModificationSchema = z.object({
  modificationId: z.string().uuid(),
  summary: z.string().min(1).max(200),
  diff: RecipeDiffSchema,
  confirmLabel: z.string().min(1).max(40).default("Modifier la recette")
});
export type PendingModification = z.infer<typeof PendingModificationSchema>;

// ---------------------------------------------------------------------------
// Assistant reply — the JSON the model must return.
// ---------------------------------------------------------------------------
export const AssistantReplySchema = z.object({
  reply: z.string().min(1).max(4_000),
  suggestions: SuggestionGroupSchema.nullable().optional(),
  // For requests that ADD content (sauce, side, extra step), the assistant
  // emits the structured diff directly here. The route persists it onto
  // chat_messages.pending_modification_json so the iOS card renders the
  // orange "Ajouter à la recette" CTA without needing a second turn.
  pendingModification: PendingModificationSchema.nullable().optional()
});
export type AssistantReply = z.infer<typeof AssistantReplySchema>;

// ---------------------------------------------------------------------------
// Recipe context (compact projection of a recipe sent to the model).
// ---------------------------------------------------------------------------
export type RecipeContextIngredient = {
  id: string;
  name: string;
  amount: string | null;
  unit: string | null;
  isSwapped: boolean;
  originName: string | null;
};

export type RecipeContextStep = {
  id: string;
  title: string | null;
  detail: string;
};

export type RecipeContext = {
  recipeId: string;
  title: string;
  servings: string | null;
  prepTimeMinutes: number | null;
  cookTimeMinutes: number | null;
  ingredients: RecipeContextIngredient[];
  steps: RecipeContextStep[];
  nutritionPerServing: NutritionPatch | null;
  allergens: string[];
  appliedModifications: Array<{
    id: string;
    summary: string;
    kind: string;
    appliedAt: string;
  }>;
};
