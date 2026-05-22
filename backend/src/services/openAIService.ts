import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { mkdtemp } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

import ffmpegStatic from "ffmpeg-static";

import { env, requireProvider } from "../config/env.js";
import { fetchRemoteBuffer, fetchRemoteFile } from "./generalPageService.js";
import {
  recipeImportSchema,
  sanitizeRecipeImport,
  type NormalizerInput,
  type RecipeImportResult
} from "../types/recipe.js";
import { compactTextBlocks, truncate, uniqueStrings } from "../utils/text.js";

const recipeJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "title",
    "sourceUrl",
    "remoteImageUrl",
    "ingredientDrafts",
    "stepDrafts",
    "notesText",
    "prepTimeText",
    "cookTimeText",
    "servingsText",
    "caloriesText",
    "proteinText",
    "carbsText",
    "fatText",
    "confidence",
    "needsWebFallback",
    "searchQuery",
    "inferredFromPhoto"
  ],
  properties: {
    title: { type: "string" },
    sourceUrl: { type: "string" },
    creatorHandle: { type: "string" },
    remoteImageUrl: { type: "string" },
    ingredientDrafts: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["amount", "unit", "name", "nutritionQuery", "group"],
        properties: {
          amount: { type: "string" },
          unit: { type: "string" },
          name: { type: "string" },
          nutritionQuery: { type: "string" },
          group: { type: "string" }
        }
      }
    },
    stepDrafts: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["detail", "section"],
        properties: {
          detail: { type: "string" },
          section: { type: "string" }
        }
      }
    },
    notesText: { type: "string" },
    prepTimeText: { type: "string" },
    cookTimeText: { type: "string" },
    servingsText: { type: "string" },
    caloriesText: { type: "string" },
    proteinText: { type: "string" },
    carbsText: { type: "string" },
    fatText: { type: "string" },
    confidence: {
      type: "string",
      enum: ["low", "medium", "high"]
    },
    confidenceScore: {
      type: "number",
      minimum: 0,
      maximum: 1
    },
    needsWebFallback: { type: "boolean" },
    searchQuery: { type: "string" },
    inferredFromPhoto: { type: "boolean" },
    flags: {
      type: "object",
      additionalProperties: false,
      required: [
        "usedExplicitIngredients",
        "usedInferredIngredients",
        "generatedSteps",
        "generatedNutrition",
        "needsReview"
      ],
      properties: {
        usedExplicitIngredients: { type: "boolean" },
        usedInferredIngredients: { type: "boolean" },
        generatedSteps: { type: "boolean" },
        generatedNutrition: { type: "boolean" },
        needsReview: { type: "boolean" }
      }
    }
  }
} as const;
const execFileAsync = promisify(execFile);
const ffmpegPath = ffmpegStatic as unknown as string | null;

export async function normalizeRecipeFromContext(
  input: NormalizerInput,
  options?: {
    timeoutMs?: number;
  }
): Promise<RecipeImportResult> {
  requireProvider("openAI");
  const imageDataUrl = await resolveNormalizationImageDataUrl(input, options?.timeoutMs);

  const normalizedRecipe = await requestStructuredRecipeFromOpenAI({
    userPrompt: buildNormalizationPrompt(input),
    imageDataUrl,
    timeoutMs: options?.timeoutMs,
    systemInstructions: [
      "# RÔLE",
      "Tu reconstruis la recette EXACTE de la vidéo, PAS une recette générique du même plat.",
      "Le test de réussite : un utilisateur qui regarde la vidéo doit reconnaître TON titre, TES ingrédients et TES étapes comme étant ceux de la vidéo, pas une version standardisée trouvable sur Marmiton.",
      "Réponds uniquement avec un JSON valide respectant strictement le schéma. Écris en français.",
      "",
      "# FOOD-CHECK D'ABORD (BLOQUANT)",
      "Avant TOUTE extraction, juge si le contenu est une recette de cuisine.",
      "Indices POSITIFS : présence d'ingrédients alimentaires nommés (farine, poulet, sauce…), gestes de cuisine (mélanger, cuire, frire, mariner…), unités culinaires (g, ml, cuillère, pincée…), nom de plat clair.",
      "Indices NÉGATIFS : tutoriel de maquillage / DIY / produits non comestibles, vlog sans contenu cuisine, mèmes, contenu purement promotionnel, code promo seul.",
      "DÉCISION :",
      "  - Si tu n'identifies AUCUN indice positif fort → renvoie un JSON avec `title=\"\"`, `ingredientDrafts=[]`, `stepDrafts=[]`, `confidence=\"low\"`, `confidenceScore=0`. N'invente PAS pour sauver.",
      "  - Si tu identifies au moins UN plat probable + 2 ingrédients alimentaires → continue.",
      "Aucune autre règle ci-dessous ne doit te faire ignorer ce check.",
      "",
      "# RÈGLE ZÉRO — CITATION STRICTE (ANTI-HALLUCINATION)",
      "Ta fonction première est de RECOPIER la recette telle qu'elle est dans la légende ou l'audio, PAS de générer la recette mentalement.",
      "Avant d'écrire CHAQUE ingrédient :",
      "  1. Trouve dans la légende OU le transcript audio la phrase qui le mentionne.",
      "  2. Si tu ne trouves AUCUNE mention de cet ingrédient dans le texte source → NE L'AJOUTE PAS. Tu as inventé.",
      "  3. Recopie la quantité ET l'unité EXACTEMENT comme écrites — pas d'arrondi, pas de conversion, pas d'estimation. `300g` reste `300g`. `6g` reste `6g`. `1 C.A.C` reste `1 cuillère à café`. `30g` ne devient PAS `80g`.",
      "  4. Si la légende dit `300g de farine`, tu écris `amount=\"300\", unit=\"g\", name=\"Farine\"`. Pas `200g`, pas `350g`, pas `farine (estimée)`.",
      "Avant d'écrire CHAQUE étape :",
      "  1. Identifie l'étape correspondante dans le texte source (numérotée 1), 2), ⭐, etc.).",
      "  2. Reformule en français impératif culinaire propre, mais préserve les VERBES et les ORDRES de grandeur (durées, températures) exactement.",
      "  3. Tu peux ajouter une étape implicite (préchauffage, repos) UNIQUEMENT si la recette ne fonctionne pas sans — et tu marques `flags.generatedSteps=true`.",
      "INTERDICTIONS ABSOLUES :",
      "  - INTERDIT d'inventer un ingrédient qui n'est pas dans le texte (ex: ajouter `crème épaisse 100g` si nulle part on ne parle de crème).",
      "  - INTERDIT d'arrondir ou de moyenner depuis une recette générique du même plat (`30g` ne devient PAS `50g` parce que `50g` est plus courant).",
      "  - INTERDIT de remplacer une quantité par une approximation (`1 c.à.c` ne devient PAS `80g`).",
      "  - INTERDIT d'omettre un ingrédient présent dans le texte sous prétexte qu'il `complique` la recette.",
      "  - INTERDIT de fusionner deux ingrédients en un (`fromage qui rit` ≠ `fromage frais` ≠ `Kiri`).",
      "Si tu hésites entre deux quantités possibles, choisis celle qui figure LITTÉRALEMENT dans le texte source. Si tu hésites sur la présence d'un ingrédient, abstiens-toi de l'ajouter.",
      "",
      "# PRINCIPE DE FIDÉLITÉ (LE PLUS IMPORTANT)",
      "La VIDÉO est la source de vérité absolue. Ta mission n'est PAS de générer une recette canonique du plat, mais de transcrire fidèlement ce que le cuisinier de la vidéo fait, avec ses ingrédients spécifiques et ses gestes signature.",
      "Tu n'inventes RIEN si tu as la donnée. Tu ne génériscises RIEN. Tu ne supprimes RIEN d'utile.",
      "",
      "# RÈGLE DE COMPLÉTION (quand la description / l'audio sont incomplets)",
      "Si tu identifies CLAIREMENT un plat (titre du plat connu ET au moins 2 ingrédients signature présents) MAIS qu'il manque des éléments triviaux pour cuisiner, tu PEUX compléter — uniquement avec :",
      "  - Évidences techniques : sel, poivre, eau, huile de cuisson, beurre quand on voit faire revenir, sucre s'il y a des œufs/farine pour un gâteau, levure pour une pâte qui lève, etc.",
      "  - Étapes implicites mais nécessaires : préchauffer le four, repos de la pâte, dressage, refroidissement.",
      "  - Quantités plausibles pour un plat standard 4 personnes : 80g de pâtes/personne, 150g de viande/personne, 1 c. à café d'épice/personne, etc.",
      "Tu marques TOUT élément complété via `flags.usedInferredIngredients=true` ou `flags.generatedSteps=true` + une note brève dans `notesText` (\"Quantités estimées pour 4 personnes\", \"Étape de préchauffage ajoutée\").",
      "Tu ne combles JAMAIS un ingrédient signature manquant (provolone, gochujang, ribeye…) à partir d'une recette générique — si l'ingrédient signature n'est pas mentionné, c'est qu'il n'est probablement pas dans cette version du plat.",
      "",
      "# FORMATS DE CAPTION TIKTOK / INSTAGRAM (à gérer naturellement)",
      "Les créateurs utilisent des conventions très variées. Tu DOIS les reconnaître toutes :",
      "  - Bullets de section : `•`, `·`, `*`, `▪`, `◦`, `‣`, `⁃`, et aussi les emojis décoratifs `⭐`, `✨`, `🔥`, `👇`, `🥩`, `🍳`, `💪` (avec OU sans espace après, en majuscule ou non).",
      "  - Bullets d'ingrédient : `-`, `–`, `—`, `*`, `•`, `→`, parfois rien du tout (juste un retour ligne).",
      "  - Sections avec colonnes (`Sauce :`, `Pour la pâte :`) ET sections sans colonne (`•Marinade poulet`, `## Garniture`).",
      "  - Abréviations d'unités : `c.s` / `c.c` / `cs` / `cc` / `cas` / `cac` (= cuillère à soupe / café), `g` / `gr` / `gramme`, `ml` / `cl` / `l`.",
      "  - Quantités prononcées sans unité : `3 oignons`, `2 œufs`, `une pincée de sel`.",
      "  - Référence à une autre vidéo (`-> naan voir sur mon compte`, `recette du pain dans la story`) : c'est un INGRÉDIENT EXTERNE — utilise le nom du plat externe comme nom d'ingrédient (`pain naan`), pas la phrase d'instruction.",
      "  - Listes inline : `Sauce: crème, moutarde, citron` → 3 ingrédients distincts dans la section Sauce.",
      "Sois LIBÉRAL dans ta tolérance aux formats — la même règle s'applique : si le pattern ressemble à une liste d'ingrédients ou une section, traite-le comme tel.",
      "",
      "Si la vidéo n'est clairement pas alimentaire après le FOOD-CHECK, renvoie un résultat vide avec confidence='low'.",
      "",
      "# SOURCES (HIÉRARCHIE STRICTE)",
      "Tu peux recevoir plusieurs sources textuelles différentes. Voici leur ordre de fiabilité :",
      "1. **Digest audio structuré** (champs DISH, SPECIFICITY, INGREDIENTS_EXPLICIT, INGREDIENTS_IMPLIED, ACTIONS_SEQUENCE, SIGNATURE_GESTURES, NOISE_DETECTED) : SOURCE DE VÉRITÉ ABSOLUE quand il est présent. Tu DOIS le respecter intégralement. INGREDIENTS_EXPLICIT et ACTIONS_SEQUENCE sont à reproduire fidèlement.",
      "2. **Texte social principal / Légende** : la description écrite par le créateur sous la vidéo. C'est SOUVENT la source la plus précise et structurée — quantités exactes, sections nommées, marques. Quand elle existe et qu'elle ressemble à une recette, **elle gagne sur tout le reste**.",
      "3. **Sous-titres** (`subtitlesText`) : les sous-titres uploadés par le créateur ou auto-générés par TikTok. Souvent ils contiennent les **text overlays** (les mots affichés à l'écran pendant la cuisson, ex: `200g de farine`, `25 min de cuisson`) qui ne sont nulle part ailleurs. C'est une source de PRÉCISION FORTE pour les quantités, à exploiter en complément.",
      "4. **Transcription audio brute** (`transcript`) : la parole du créateur retranscrite par Whisper. Moins précise que la légende sur les quantités (le créateur abrège souvent — « une c. à café », « un peu de »), mais critique pour la SÉQUENCE D'ACTIONS et les gestes signature.",
      "5. **Pages web fallback** (`pageTextContent`) : SEULEMENT pour combler une recette identifiée mais incomplète. JAMAIS pour remplacer la recette de la vidéo par une version 'standard' du même plat.",
      "6. **Connaissance générale du plat** : DERNIER recours, uniquement pour des évidences techniques (sel, poivre, huile de cuisson, eau). JAMAIS pour des ingrédients signature.",
      "",
      "STRATÉGIE DE FUSION DES SOURCES :",
      "- Si la légende contient déjà une liste structurée d'ingrédients avec sections (`⭐ INGRÉDIENTS / ⭐ MARINADE / ⭐ PANURE`), **prends-la comme socle**. Les sous-titres et l'audio servent alors à VÉRIFIER et à compléter les éventuelles oublis.",
      "- Si la légende est courte (`Sandwich raclette de fou 🤤 #recettehiver`) mais que l'audio détaille la recette, **bâtis depuis l'audio** et utilise la légende uniquement pour le titre.",
      "- Si trois sources mentionnent un même ingrédient avec des quantités différentes, prends celle de la LÉGENDE (la plus écrite/relue), puis SOUS-TITRES, puis AUDIO en dernier. Mais ne MIXE pas — choisis-en une.",
      "- Si une source mentionne un ingrédient et les deux autres pas, garde-le (ce n'est pas une contradiction, c'est juste qu'il n'a pas été nommé partout).",
      "",
      "# RÈGLE ANTI-COPIE BRUTE",
      "Ne copie JAMAIS un fragment parlé brut dans `ingredientDraft.name` ou `stepDraft.detail`.",
      "Si un nom d'ingrédient ressemble à une phrase parlée ('à café', 'à soupe', 'ce moment-là', 'en plusieurs fois', 'papier journal', 'et après ça'), c'est un artefact : corrige-le ou jette-le.",
      "Interprète 'à café' = 'cuillère à café', 'à soupe' = 'cuillère à soupe'.",
      "Les ustensiles (papier, film, assiette, poêle, rouleau, spatule) ne sont JAMAIS des ingrédients.",
      "Aucun fragment listé dans NOISE_DETECTED du digest ne doit apparaître dans la recette.",
      "",
      "# TITRE",
      "Le titre = le nom complet et SPÉCIFIQUE du plat de la vidéo. JAMAIS un mot de catégorie seul.",
      "",
      "❌ 'Sandwich'             ✓ 'Philly cheesesteak'",
      "❌ 'Burger'               ✓ 'Smash burger cheddar bacon'",
      "❌ 'Pizza'                ✓ 'Pizza tartiflette à la poêle'",
      "❌ 'Tacos'                ✓ 'Tacos al pastor'",
      "❌ 'Salade'               ✓ 'Salade César au poulet grillé'",
      "❌ 'Pasta' / 'Pâtes'      ✓ 'Pâtes carbonara'",
      "❌ 'Wrap'                 ✓ 'Wrap poulet César'",
      "❌ 'Curry'                ✓ 'Butter chicken'",
      "",
      "Si DISH du digest est précis (SPECIFICITY=high), tu DOIS le réutiliser tel quel.",
      "Si DISH est vague mais que SIGNATURE_GESTURES ou INGREDIENTS_EXPLICIT révèlent le vrai plat, compose le titre depuis ces indices.",
      "Si même là c'est impossible : `needsWebFallback=true` + `searchQuery` riche basé sur head + ingrédients distinctifs.",
      "Pas de liste d'ingrédients dans le titre, pas de hashtags, pas d'URL. Si un auteur social est connu, renseigne `creatorHandle` au format @nom.",
      "",
      "# INGRÉDIENTS — RÈGLE DE FIDÉLITÉ",
      "**RÈGLE 1 (CRITIQUE)** — TOUT ingrédient présent dans INGREDIENTS_EXPLICIT du digest DOIT figurer dans `ingredientDrafts` avec le NOM EXACT prononcé. Interdiction absolue de génériciser :",
      "  ❌ 'provolone' → 'fromage'",
      "  ❌ 'baguette à hoagie' → 'pain'",
      "  ❌ 'ribeye' / 'entrecôte' → 'viande de bœuf'",
      "  ❌ 'Kiri' → 'fromage frais'",
      "  ❌ 'gochujang' → 'sauce piquante'",
      "  ❌ 'panko' → 'chapelure'",
      "  ❌ 'burrata' → 'mozzarella'",
      "  ❌ 'rigatoni' / 'penne' / 'spaghetti' → 'pâtes'",
      "  ❌ 'crème liquide entière' / 'crème fraîche épaisse' → 'crème'",
      "  ❌ 'cajun seasoning' / 'paprika fumé' / 'cumin moulu' → 'épices'",
      "  ❌ 'pain naan' / 'pain burger brioché' / 'tortilla maïs' / 'baguette' / 'pain pita' → 'pain'",
      "  ❌ 'cheddar mature' / 'mozzarella râpée' / 'parmesan' / 'fromage à raclette' / 'fromage à croque' → 'fromage'",
      "  ❌ remplacer un type de fromage par un autre type différent ('raclette' ≠ 'cheddar' ≠ 'mozzarella' — préserve EXACTEMENT le fromage prononcé)",
      "  ❌ 'tenders de poulet' / 'blanc de poulet' / 'escalope de poulet' → 'poulet'",
      "  ❌ 'oignon rouge' / 'oignon doux' / 'échalote' → 'oignon'",
      "  ❌ 'mayonnaise' / 'aïoli' / 'sauce yaourt' → 'sauce'",
      "",
      "**RÈGLE 2** — Tu peux AJOUTER des ingrédients seulement s'ils sont :",
      "  (a) techniquement nécessaires et triviaux (sel, poivre, huile de cuisson, eau),",
      "  (b) clairement implicites (sauter à la poêle ⇒ huile/beurre),",
      "  (c) listés dans INGREDIENTS_IMPLIED du digest.",
      "Tout ingrédient ajouté doit être marqué via `flags.usedInferredIngredients=true`.",
      "",
      "**RÈGLE 3** — Tu ne peux JAMAIS supprimer un ingrédient du digest sous prétexte qu'il 'complique' ou n'est 'pas standard' pour le plat. La vidéo a la priorité.",
      "",
      "**RÈGLE 4** — Quantités : reproduis celles prononcées. Sinon, estime de façon réaliste pour 4 portions et indique brièvement '(estimé)' dans `notesText`.",
      "",
      "**RÈGLE 4bis (CRITIQUE) — QUANTITÉS TOTALES, JAMAIS PAR PORTION** —",
      "Toutes les quantités d'ingrédients représentent le TOTAL pour la recette ENTIÈRE (ce qu'il faut acheter et utiliser au total), JAMAIS par portion individuelle.",
      "- Si la vidéo donne des quantités totales (« 250 g de pâtes pour 3 personnes ») : reproduis-les telles quelles → `amount='250'`, `unit='g'`.",
      "- Si la vidéo donne des quantités par personne : multiplie par le nombre de personnes servies.",
      "- Si tu dois estimer : raisonne pour 4 personnes par défaut et donne le TOTAL pour 4.",
      "- `servingsText` = nombre TOTAL de personnes servies par la recette finale (ex: '4 personnes', '6 portions').",
      "",
      "**INTERDIT ABSOLU — DÉCIMALES SUSPECTES**",
      "Tu ne dois JAMAIS produire des quantités du type `0.3`, `0.7`, `1.3`, `2.7`, `13.3`, `33.3`, `66.7`, `83.3`, `133.3`. Ce sont les signatures mathématiques d'une division par 3 (ou 7) faite à tort. Si tu es tenté de produire un de ces nombres : tu as divisé par portion par erreur.",
      "Quand tu détectes ce piège : MULTIPLIE par le nombre de portions et arrondis à des quantités de cuisine naturelles :",
      "  - poids/volume : entiers ou multiples de 5/10/25/50/100 (5g, 10g, 50g, 100g, 250g, 500g, 1 kg ; 10ml, 50ml, 100ml, 250ml, 500ml, 1 L).",
      "  - ingrédients comptables (œuf, citron, oignon, gousse, tranche, tortilla, pain) : entiers >= 1, jamais de décimale.",
      "  - cuillères : entiers ou demi-entiers (`1`, `1/2`, `2`, `1.5`).",
      "",
      "**Format** — un seul ingrédient par objet `ingredientDraft`, jamais plusieurs fusionnés. Jamais '/', ',', '+', '&', 'et' ou '...' dans le `name`.",
      "`nutritionQuery` = nom court en anglais USDA (ex: 'provolone cheese', 'ribeye steak', 'gochujang').",
      "",
      "# ÉTAPES — RÈGLE DE FIDÉLITÉ",
      "**RÈGLE 1** — Les étapes DOIVENT suivre l'ordre et le contenu de ACTIONS_SEQUENCE du digest. Tu adaptes le style (impératif culinaire propre, max 2-3 phrases par étape) mais tu ne réinventes PAS la séquence.",
      "",
      "**RÈGLE 2** — Tout SIGNATURE_GESTURE du digest DOIT apparaître comme étape distincte avec son détail (ex : 'Aplatir le steak haché à la spatule sur la plancha brûlante 30 secondes pour obtenir une croûte caramélisée' — pas juste 'cuire le steak').",
      "",
      "**RÈGLE 3** — Tu peux ajouter des étapes UNIQUEMENT si elles sont :",
      "  (a) indispensables techniquement et absentes (préchauffer, repos, dressage),",
      "  (b) implicites visuellement.",
      "Tu marques alors `flags.generatedSteps=true`.",
      "",
      "**RÈGLE 4** — Aucune étape ne doit contenir : timestamps, flèches '-->', 'abonne-toi', 'bon app', 'lien en bio', hashtags, 'ce moment-là', phrases parlées brutes, ni d'éléments listés dans NOISE_DETECTED du digest.",
      "",
      "**RÈGLE 5** — Si ACTIONS_SEQUENCE contient moins de 4 actions, complète avec les phases implicites strictement nécessaires (préparation des ingrédients, cuisson, dressage) et marque `flags.generatedSteps=true`.",
      "",
      "Minimum 6 étapes pour un plat standard. Indique température et durée quand elles sont mentionnées dans le digest ou raisonnablement déductibles. Chaque étape = une seule action concrète.",
      "",
      "# GROUPEMENT DES INGRÉDIENTS ET ÉTAPES (OBLIGATOIRE QUAND APPLICABLE)",
      "Analyse le digest (INGREDIENTS_EXPLICIT + ACTIONS_SEQUENCE) et/ou la légende pour détecter les sous-préparations distinctes. Sous-préparations typiques : Marinade, Pâte, Sauce, Garniture, Salade, Dressage, Montage, Cuisson, Accompagnement.",
      "",
      "**RÈGLE DE GROUPEMENT** —",
      "- Si la vidéo contient ≥2 sous-préparations distinctes (ex: marinade du poulet + sauce crémeuse + salade + montage), tu DOIS remplir le champ `group` de CHAQUE `ingredientDraft` avec le label de sa sous-préparation (ex: 'Marinade poulet', 'Sauce crémeuse', 'Salade', 'Montage').",
      "- Utilise exactement le MÊME label pour tous les ingrédients d'une même sous-préparation.",
      "- Tu DOIS aussi remplir le champ `section` de la PREMIÈRE étape de chaque sous-préparation avec le MÊME label que le `group` correspondant. Les étapes suivantes de cette sous-préparation ont `section` vide.",
      "- Un même ingrédient peut apparaître dans PLUSIEURS groupes avec des quantités différentes (ex: 'crème fraîche' 4 c.s. pour la Sauce + 2 c.s. pour la Salade). Ce sont deux `ingredientDraft` distincts avec le même `name` mais des `group` différents.",
      "- Si la recette est réellement linéaire (un seul bloc cohérent, pas de sous-préparations), laisse `group` et `section` à chaîne vide.",
      "",
      "EXEMPLE — chicken burger avec marinade + sauce + salade + montage :",
      "  ingredientDrafts: [",
      "    { amount:'2', unit:'c.s.', name:'Sauce barbecue', nutritionQuery:'bbq sauce', group:'Marinade poulet' },",
      "    { amount:'1', unit:'c.s.', name:'Sauce soja sucrée', nutritionQuery:'sweet soy sauce', group:'Marinade poulet' },",
      "    { amount:'400', unit:'g', name:'Blanc de poulet', nutritionQuery:'chicken breast', group:'Marinade poulet' },",
      "    { amount:'3', unit:'c.s.', name:'Crème fraîche', nutritionQuery:'sour cream', group:'Sauce crémeuse' },",
      "    { amount:'4', unit:'c.s.', name:'Mayonnaise', nutritionQuery:'mayonnaise', group:'Sauce crémeuse' },",
      "    { amount:'2', unit:'c.s.', name:'Crème fraîche', nutritionQuery:'sour cream', group:'Salade' },",
      "    { amount:'2', unit:'', name:'Pain burger', nutritionQuery:'hamburger bun', group:'Montage' }",
      "  ]",
      "  stepDrafts: [",
      "    { detail:'Mélange la sauce barbecue, la sauce soja sucrée et les épices dans un bol.', section:'Marinade poulet' },",
      "    { detail:'Ajoute les escalopes de poulet, masse et laisse mariner 30 min au frigo.', section:'' },",
      "    { detail:'Fouette la crème fraîche et la mayonnaise jusqu\\'à obtenir une sauce lisse.', section:'Sauce crémeuse' },",
      "    ...",
      "  ]",
      "",
      "# NUTRITION",
      "Obligatoire pour tout contenu alimentaire : `caloriesText`, `proteinText`, `carbsText`, `fatText` avec une estimation réaliste par portion, cohérente avec les ingrédients finaux.",
      "Vérifie la cohérence calories / macros ; corrige plutôt que renvoyer une nutrition vide.",
      "",
      "# FLAGS",
      "`flags.usedExplicitIngredients` = true si au moins un ingrédient vient du digest/texte explicite (devrait être true dans 99% des cas).",
      "`flags.usedInferredIngredients` = true si tu as ajouté des ingrédients non listés.",
      "`flags.generatedSteps` = true si tu as ajouté ou reformulé librement des étapes au-delà de ACTIONS_SEQUENCE.",
      "`flags.generatedNutrition` = true pour toute recette alimentaire.",
      "`confidenceScore` entre 0 et 1 selon la solidité du plat détecté et la part de déduction.",
      "",
      "# EXEMPLE COMPLET (à internaliser comme référence du comportement attendu)",
      "Texte source (légende TikTok) :",
      "```",
      "👇SANDWICH NAAN 👇",
      "⭐ INGRÉDIENTS",
      "- 300g de farine",
      "- 6g de levure déshydratée",
      "- 1 C.A.C de levure chimique",
      "- 125g de yaourt nature",
      "- 1 C.A.C de sucre",
      "- 30g de beurre mou",
      "- 60ml d'eau tiède",
      "- 10 portions de fromage qui rit",
      "⭐ MARINADE",
      "- 3 escalopes de poulet",
      "- 1 c.a.s de sauce soja salé",
      "- 1 c.a.s de sauce soja sucré",
      "- sel, poivre, paprika, ail semoule",
      "⭐ PANURE",
      "- 150g de farine",
      "- 150g de chapelure",
      "- 4 œufs battus",
      "```",
      "JSON attendu (exemple ABRÉGÉ — montre la structure, pas tous les champs) :",
      "```",
      "{",
      "  \"title\": \"Sandwich naan poulet pané\",",
      "  \"servingsText\": \"4 sandwiches\",",
      "  \"ingredientDrafts\": [",
      "    { \"amount\": \"300\", \"unit\": \"g\", \"name\": \"Farine\", \"nutritionQuery\": \"flour\", \"group\": \"Naan\" },",
      "    { \"amount\": \"6\", \"unit\": \"g\", \"name\": \"Levure déshydratée\", \"nutritionQuery\": \"dry yeast\", \"group\": \"Naan\" },",
      "    { \"amount\": \"1\", \"unit\": \"c. à café\", \"name\": \"Levure chimique\", \"nutritionQuery\": \"baking powder\", \"group\": \"Naan\" },",
      "    { \"amount\": \"125\", \"unit\": \"g\", \"name\": \"Yaourt nature\", \"nutritionQuery\": \"plain yogurt\", \"group\": \"Naan\" },",
      "    { \"amount\": \"1\", \"unit\": \"c. à café\", \"name\": \"Sucre\", \"nutritionQuery\": \"sugar\", \"group\": \"Naan\" },",
      "    { \"amount\": \"30\", \"unit\": \"g\", \"name\": \"Beurre mou\", \"nutritionQuery\": \"butter\", \"group\": \"Naan\" },",
      "    { \"amount\": \"60\", \"unit\": \"ml\", \"name\": \"Eau tiède\", \"nutritionQuery\": \"water\", \"group\": \"Naan\" },",
      "    { \"amount\": \"10\", \"unit\": \"portions\", \"name\": \"Fromage qui rit\", \"nutritionQuery\": \"laughing cow cheese\", \"group\": \"Naan\" },",
      "    { \"amount\": \"3\", \"unit\": \"\", \"name\": \"Escalopes de poulet\", \"nutritionQuery\": \"chicken breast\", \"group\": \"Marinade\" },",
      "    { \"amount\": \"1\", \"unit\": \"c. à soupe\", \"name\": \"Sauce soja salé\", \"nutritionQuery\": \"soy sauce\", \"group\": \"Marinade\" },",
      "    { \"amount\": \"1\", \"unit\": \"c. à soupe\", \"name\": \"Sauce soja sucré\", \"nutritionQuery\": \"sweet soy sauce\", \"group\": \"Marinade\" },",
      "    { \"amount\": \"150\", \"unit\": \"g\", \"name\": \"Farine\", \"nutritionQuery\": \"flour\", \"group\": \"Panure\" },",
      "    { \"amount\": \"150\", \"unit\": \"g\", \"name\": \"Chapelure\", \"nutritionQuery\": \"breadcrumbs\", \"group\": \"Panure\" },",
      "    { \"amount\": \"4\", \"unit\": \"\", \"name\": \"Œufs\", \"nutritionQuery\": \"egg\", \"group\": \"Panure\" }",
      "  ],",
      "  \"stepDrafts\": [",
      "    { \"detail\": \"Diluer la levure déshydratée dans 4 c. à soupe d'eau tiède et laisser agir 10 minutes.\", \"section\": \"Naan\" },",
      "    { \"detail\": \"Mélanger farine, sel, sucre et levure chimique dans la cuve du robot.\", \"section\": \"\" },",
      "    { \"detail\": \"Mariner les escalopes 1h au frais avec sauce soja salée, sauce soja sucrée, sel, poivre, paprika et ail.\", \"section\": \"Marinade\" },",
      "    { \"detail\": \"Enrober les tenders dans l'œuf, puis dans la farine, puis à nouveau dans l'œuf, puis dans la chapelure.\", \"section\": \"Panure\" }",
      "  ]",
      "}",
      "```",
      "Notes sur cet exemple :",
      "  - Chaque ingrédient du texte source est reproduit avec sa QUANTITÉ EXACTE (300g, 6g, 1 C.A.C, 30g, 4 œufs…) — pas d'arrondi vers une valeur générique.",
      "  - Les sections `⭐ INGRÉDIENTS` / `⭐ MARINADE` / `⭐ PANURE` sont devenues `group` distincts (`Naan` / `Marinade` / `Panure`).",
      "  - La même quantité d'ingrédient peut apparaître dans deux groupes (`Farine` 300g dans `Naan` + `Farine` 150g dans `Panure`) — deux entrées séparées.",
      "  - Le titre `Sandwich naan poulet pané` est spécifique, pas juste `Sandwich`.",
      "  - Aucun ingrédient n'a été inventé (pas de `crème épaisse`, pas de `cumin`, pas de `oignon` non mentionné).",
      "  - Les abréviations `C.A.C` et `c.a.s` sont devenues `c. à café` et `c. à soupe`.",
      "",
      "# VALIDATION FINALE — FIDÉLITÉ (OBLIGATOIRE avant d'émettre le JSON)",
      "Vérifie ces 7 points point par point. Si l'un échoue, CORRIGE avant d'émettre :",
      "",
      "[FID-1] Chaque entrée de INGREDIENTS_EXPLICIT du digest est présente dans `ingredientDrafts` avec son nom spécifique. Si une entrée manque, AJOUTE-LA.",
      "[FID-2] Chaque entrée de ACTIONS_SEQUENCE du digest a un step correspondant dans le bon ordre. Si une étape manque, AJOUTE-LA.",
      "[FID-3] Chaque SIGNATURE_GESTURE du digest est présent dans une étape avec son détail.",
      "[FID-4] Aucun fragment de NOISE_DETECTED n'apparaît dans `title`, `ingredientDrafts`, `stepDrafts` ou `notesText`.",
      "[FID-5] Aucun nom d'ingrédient n'a été génériquisé (provolone→fromage, ribeye→bœuf, panko→chapelure, gochujang→sauce piquante, rigatoni→pâtes, cheddar→fromage, cajun seasoning→épices, blanc de poulet→poulet, etc.).",
      "[FID-6] Le titre n'est pas un mot de catégorie seul (sandwich, burger, pizza, pasta, salade, tacos, wrap, bowl, curry, ramen, gratin, quiche, omelette).",
      "[FID-7] Si tu as ajouté des ingrédients/étapes au-delà du digest, `flags.usedInferredIngredients` et `flags.generatedSteps` sont à true et tu listes brièvement dans `notesText` ce qui est inféré.",
      "[FID-8] Si la vidéo contient ≥2 sous-préparations distinctes, CHAQUE ingredientDraft a un `group` non vide. Les labels `group` et `section` sont cohérents (chaque `section` correspond à un `group` utilisé au moins une fois). Si la recette est linéaire, `group` et `section` restent vides partout.",
      "[FID-9] Toutes les quantités sont des TOTAUX pour la recette entière (jamais par portion). Aucune quantité ne se termine par .3, .33, .7, .67, .333 ou similaire — ces décimales révèlent une division par 3 ou par 7 faite par erreur. Multiplie par le nombre de portions et arrondis à des quantités naturelles de cuisine.",
      "[FID-10] Pour chaque ingrédient comptable (œuf, citron, oignon, gousse d'ail, tranche, tortilla, pain, escalope, filet, blanc de poulet, tomate, pomme, échalote), `amount` est un entier >= 1, jamais une fraction décimale. `servingsText` indique le nombre TOTAL de personnes servies (jamais '1 portion' si la recette nourrit 4 personnes).",
      "[FID-11 — ANTI-HALLUCINATION] Pour CHAQUE `ingredientDraft` :",
      "  (a) son `name` correspond à une mention LITTÉRALE dans le texte source (légende OU transcript). Si tu ne retrouves pas le mot dans le texte, supprime l'ingrédient.",
      "  (b) son `amount` correspond EXACTEMENT à la quantité écrite dans le texte source — pas d'arrondi (`30g` reste `30`, pas `50`), pas d'inflation (`1 c.à.c` reste `1`, pas `80`), pas de conversion silencieuse.",
      "  (c) si un ingrédient signature n'est pas dans le texte mais est trivial techniquement (sel, poivre, huile de cuisson, eau), tu peux l'ajouter et marquer `flags.usedInferredIngredients=true`.",
      "  Refuse de produire un ingredientDraft pour `crème épaisse`, `cumin`, `lait`, `sucre 80g`, etc. si aucun de ces mots n'apparaît dans le texte source.",
      "",
      "Ne renvoie JAMAIS une recette qui s'éloigne du digest sans raison technique justifiable. Si la recette est encore incomplète malgré le contexte, enrichis-la plutôt que d'activer `needsWebFallback` en échappatoire — sauf si le titre reste générique malgré tes efforts."
    ]
  });

  return sanitizeRecipeImport({
    ...normalizedRecipe,
    creatorHandle: normalizedRecipe.creatorHandle || input.socialAuthor
  });
}

/**
 * Preservation-mode normalization. Used when the recipe compiler has
 * already parsed a structured recipe but needs LLM help for specific
 * gaps (nutrition, a few missing steps, etc.).
 *
 * The system prompt explicitly forbids restructuring, rewriting, or
 * flattening sections. The LLM is told to ONLY clean/normalize and
 * fill the gaps specified.
 */
export async function normalizeRecipePreservationMode(
  input: NormalizerInput,
  compilerRecipe: RecipeImportResult,
  options?: {
    timeoutMs?: number;
    fillNutrition?: boolean;
    fillSteps?: boolean;
  }
): Promise<RecipeImportResult> {
  requireProvider("openAI");
  const imageDataUrl = await resolveNormalizationImageDataUrl(input, options?.timeoutMs);

  // Build a structured summary of what the compiler has already produced
  const sectionSummary = buildCompilerSectionSummary(compilerRecipe);
  const gaps: string[] = [];
  if (options?.fillNutrition !== false) gaps.push("nutrition (calories, protéines, glucides, lipides)");
  if (options?.fillSteps) gaps.push("étapes manquantes");

  const normalizedRecipe = await requestStructuredRecipeFromOpenAI({
    userPrompt: buildNormalizationPrompt(input),
    imageDataUrl,
    timeoutMs: options?.timeoutMs,
    systemInstructions: [
      "# MODE PRÉSERVATION (CRITIQUE)",
      "La recette suivante a DÉJÀ été structurée par un compilateur déterministe à partir de la source primaire.",
      "Tu NE DOIS PAS restructurer, réécrire, ou aplatir cette recette.",
      "Tu NE DOIS PAS changer les noms d'ingrédients, les quantités ni leur ordre.",
      "Tu NE DOIS PAS fusionner ou supprimer des sections/groupes existants.",
      "",
      "# TON RÔLE EST LIMITÉ À :",
      `- Combler UNIQUEMENT ces lacunes : ${gaps.join(", ") || "aucune — vérifie seulement"}.`,
      "- Corriger des fautes d'orthographe évidentes.",
      "- Compléter le titre s'il est vide ou trop générique.",
      "- Estimer la nutrition si absente.",
      "- Ajouter des étapes UNIQUEMENT si la recette en a moins de 3.",
      "",
      "# RECETTE DÉJÀ STRUCTURÉE (NE PAS MODIFIER) :",
      sectionSummary,
      "",
      "# CONTRAINTES ABSOLUES :",
      "- Préserve TOUS les champs `group` et `section` tels quels.",
      "- Ne réduis JAMAIS la spécificité d'un ingrédient.",
      "- Si tu n'es pas sûr d'une correction → GARDE L'ORIGINAL.",
      "- Réponds uniquement avec un JSON valide respectant strictement le schéma. Écris en français.",
    ]
  });

  return sanitizeRecipeImport({
    ...normalizedRecipe,
    creatorHandle: normalizedRecipe.creatorHandle || input.socialAuthor
  });
}

function buildCompilerSectionSummary(recipe: RecipeImportResult): string {
  const groups = new Map<string, string[]>();
  for (const ingredient of recipe.ingredientDrafts) {
    const group = (ingredient.group ?? "").trim() || "(sans section)";
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group)!.push(
      `${ingredient.amount || "?"} ${ingredient.unit || ""} ${ingredient.name}`.trim()
    );
  }

  const lines: string[] = [];
  lines.push(`Titre: ${recipe.title}`);
  lines.push(`Ingrédients (${recipe.ingredientDrafts.length}) :`);
  for (const [group, ingredients] of groups) {
    lines.push(`  ${group}: ${ingredients.join(", ")}`);
  }
  lines.push(`Étapes (${recipe.stepDrafts.length}) :`);
  for (const step of recipe.stepDrafts.slice(0, 12)) {
    const prefix = step.section ? `[${step.section}] ` : "";
    lines.push(`  - ${prefix}${step.detail.slice(0, 80)}`);
  }
  return lines.join("\n");
}

export async function reviewRecipeCookability(
  input: {
    draft: RecipeImportResult;
    context: NormalizerInput;
    reviewHint?: string;
  },
  options?: {
    timeoutMs?: number;
  }
): Promise<RecipeImportResult> {
  requireProvider("openAI");

  const sanitizedDraft = sanitizeRecipeImport(input.draft);
  const imageDataUrl = await resolveNormalizationImageDataUrl(input.context, options?.timeoutMs);

  const reviewedRecipe = await requestStructuredRecipeFromOpenAI({
    userPrompt: buildCookabilityReviewPrompt(sanitizedDraft, input.context, input.reviewHint),
    imageDataUrl,
    timeoutMs: options?.timeoutMs,
    systemInstructions: [
      "Tu relis une recette déjà structurée et tu vérifies qu'une personne peut réellement la cuisiner du début à la fin.",
      "Réponds uniquement avec un JSON valide respectant strictement le schéma.",
      "Écris en français.",
      "Commence par valider le plat détecté: si le titre n'est pas un vrai plat mais que le contexte culinaire en révèle un, remplace le titre par le nom du plat.",
      "Si le contexte n'est clairement pas alimentaire, renvoie un résultat vide et n'essaie pas de sauver artificiellement une recette.",
      "Le titre doit rester court, naturel et limité au nom du plat.",
      "Conserve creatorHandle quand un auteur social crédible est disponible.",
      "Ne garde que des ingrédients réellement utiles pour cuisiner le plat.",
      "Chaque objet ingredientDraft doit représenter un seul ingrédient. Si tu vois 'emmental/cornichon', 'sauce + salade' ou toute liste dans un seul name, sépare-les en plusieurs objets.",
      "Si la recette a moins de 3 ingrédients valides ou moins de 2 étapes valides, abandonne cette extraction faible et reconstruis une recette complète autour du plat détecté.",
      "Les étapes doivent couvrir la préparation, la cuisson et l'assemblage de façon suffisante pour que la recette soit faisable. Vise au minimum 6 étapes détaillées (idéalement 6 à 12 selon la complexité du plat) avec une seule action par étape.",
      "Revois les étapes à partir des ingrédients retenus: chaque ingrédient principal doit être utilisé ou explicitement signalé comme garniture.",
      "Ignore le style oral et les formulations de la vidéo: réécris les étapes proprement depuis la liste finale d'ingrédients au lieu de recopier ce qui est dit.",
      "Garde les ingrédients explicitement mentionnés quand ils sont plausibles, puis complète seulement les manques essentiels à partir du plat détecté.",
      "Si un ingrédient essentiel ou une étape essentielle manque mais est clairement implicite dans le contexte, ajoute-le.",
      "Si plusieurs sources web sont disponibles dans le contexte, compare-les et reconstruis une version cohérente du plat en gardant les ingrédients et étapes les plus récurrents.",
      "N'ajoute pas d'éléments fantaisistes: toute déduction doit être raisonnable et, si besoin, brièvement signalée dans notesText.",
      "Supprime tout bruit social, hashtags, URLs, outros, CTA et timestamps.",
      "Déduis prudemment les portions ou petites quantités implicites si cela rend la recette et la nutrition plus cohérentes.",
      "QUANTITÉS TOTALES (CRITIQUE) — Toutes les quantités d'ingrédients sont des TOTAUX pour la recette entière, JAMAIS par portion. `servingsText` indique le nombre TOTAL de personnes servies. Si tu vois des quantités décimales suspectes (`0.3`, `1.3`, `13.3`, `33.3`, `66.7`, `83.3`), c'est qu'elles ont été divisées par 3 par erreur : multiplie-les par le nombre de portions et arrondis à des quantités naturelles (entiers ou multiples de 5/10/25/50/100).",
      "Pour les ingrédients comptables (œuf, citron, oignon, gousse, tranche, tortilla, pain, escalope, blanc de poulet, tomate), `amount` doit être un entier >= 1 — jamais une fraction décimale.",
      "ANTI-HALLUCINATION (CRITIQUE) — Pour CHAQUE ingrédient que tu gardes ou ajoutes : sa quantité doit correspondre à ce qui est ÉCRIT dans le texte source. JAMAIS d'arrondi vers une recette générique (`30g` ne devient PAS `80g`), JAMAIS d'invention d'ingrédient absent du texte (`crème épaisse`, `cumin`, `sucre 80g` ne sont ajoutés QUE si le texte les mentionne explicitement). Si tu hésites à propos d'un ingrédient, abstiens-toi.",
      "Renseigne confidenceScore entre 0 et 1 et mets à jour les flags pour refléter les ingrédients explicites, les ingrédients inférés, les étapes générées et la nutrition générée.",
      "Ne laisse jamais une recette alimentaire sans nutrition: estime toujours calories, protéines, glucides et lipides à partir de la version finale.",
      "Vérifie aussi que calories, protéines, glucides et lipides restent cohérents entre eux; si les macros ne collent pas raisonnablement avec les calories, corrige-les au lieu de vider la nutrition.",
      "GROUPEMENT (CRITIQUE) — Si la recette comporte ≥2 sous-préparations distinctes (marinade, sauce, pâte, garniture, salade, dressage, montage), tu DOIS remplir :",
      "  1. Le champ `group` de CHAQUE ingredientDraft avec le label de sa sous-préparation (ex: 'Marinade poulet', 'Sauce crémeuse', 'Salade', 'Montage').",
      "  2. Le champ `section` de la PREMIÈRE étape de chaque sous-préparation avec le MÊME label. Les étapes suivantes de la même sous-préparation ont `section` vide.",
      "Déduis les sous-préparations depuis les verbes d'action : 'mariner' → Marinade, 'mélanger la sauce' → Sauce, 'monter le burger' → Montage, etc.",
      "Utilise exactement le MÊME label pour le `group` d'un ingrédient et le `section` de l'étape qui l'utilise.",
      "Un même ingrédient peut apparaître dans plusieurs groupes (crème fraîche dans Sauce + Salade) avec des quantités différentes — crée alors deux ingredientDraft distincts.",
      "Ne force pas de groupement si la recette suit un déroulé linéaire simple (un seul bloc d'ingrédients) : laisse `group` et `section` à chaîne vide partout.",
      "Chaque étape de cuisson doit inclure la température ou l'intensité du feu quand c'est pertinent (par ex. 'à feu moyen', '180 °C').",
      "Chaque étape impliquant une durée doit mentionner un temps indicatif (par ex. '5 minutes', 'environ 10 min').",
      "Chaque ingrédient principal doit apparaître nommément dans au moins une étape. Vérifie cette règle avant de finaliser le JSON."
    ]
  });

  return sanitizeRecipeImport({
    ...reviewedRecipe,
    creatorHandle: reviewedRecipe.creatorHandle || sanitizedDraft.creatorHandle || input.context.socialAuthor
  });
}

/**
 * Pre-pass that turns a raw, speech-to-text French audio transcript into a
 * clean structured digest. The goal is to take cognitive load off the main
 * reconstruction call: the distiller fixes obvious transcription artifacts
 * (e.g. "à café" -> "cuillère à café"), drops filler/outro chunks, and hands
 * the normalizer a pre-cleaned list of dish name, ingredients, and actions.
 *
 * Returns `null` when the transcript is too short to be worth distilling or
 * when the LLM call fails: callers must fall back to the raw transcript.
 */
export async function distillTranscriptForRecipe(
  transcript: string,
  options?: {
    timeoutMs?: number;
    sourceUrl?: string;
    socialTitle?: string;
  }
): Promise<string | null> {
  const trimmed = transcript.trim();
  if (trimmed.length < 40) {
    return null;
  }

  requireProvider("openAI");

  const userPrompt = [
    "Voici la transcription audio brute d'une vidéo TikTok/Instagram de cuisine en français.",
    "Elle est parlée, bruyante, avec des répétitions, des phrases inachevées et des erreurs de reconnaissance vocale.",
    options?.socialTitle ? `Titre social : ${truncate(options.socialTitle, 180)}` : "",
    options?.sourceUrl ? `URL : ${options.sourceUrl}` : "",
    "",
    "Transcription :",
    truncate(trimmed, 6000),
    "",
    "MISSION : produire un digest STRUCTURÉ qui sera la source de vérité pour reconstruire la VRAIE recette de la vidéo (pas une recette générique).",
    "",
    "Tu dois extraire EXACTEMENT, en français, dans cet ordre, en respectant la mise en forme :",
    "",
    "1. DISH: le nom le plus PRÉCIS et COMPLET prononcé ou clairement identifiable.",
    "   - Conserve TOUS les descripteurs : nom régional ('Philly', 'napolitaine', 'thaï'), ingrédient signature ('cheddar bacon', 'truffe'), méthode ('smash', 'à la poêle'), origine.",
    "   - INTERDIT de simplifier en un mot de catégorie seul. ❌ 'Sandwich' / ✓ 'Philly cheesesteak'. ❌ 'Burger' / ✓ 'Smash burger cheddar bacon'. ❌ 'Pizza' / ✓ 'Pizza tartiflette à la poêle'.",
    "   - Si le cuisinier n'annonce pas le nom mais que les ingrédients/gestes le révèlent clairement, compose le nom toi-même à partir de ces indices.",
    "   - Si vraiment aucun descripteur n'est identifiable, écris 'INCONNU'.",
    "",
    "2. SPECIFICITY: un seul mot parmi 'high', 'medium', 'low'.",
    "   - 'high' = nom composé précis, clairement annoncé ou évident.",
    "   - 'medium' = plat reconnaissable mais avec hésitation.",
    "   - 'low' = mot générique seul ou plat indéterminé.",
    "",
    "3. INGREDIENTS_EXPLICIT: UNIQUEMENT les ingrédients réellement prononcés ou montrés dans la vidéo.",
    "   - Format : '- <nom exact prononcé, en français> [quantité si donnée] [marque si donnée]'",
    "   - Garde les noms SPÉCIFIQUES : 'provolone' (pas 'fromage'), 'baguette à hoagie' (pas 'pain'), 'ribeye' (pas 'bœuf'), 'gochujang' (pas 'sauce piquante'), 'panko' (pas 'chapelure'), 'Kiri' reste 'Kiri', 'rigatoni' (pas 'pâtes'), 'cajun seasoning' (pas 'épices').",
    "   - Corrige les artefacts de transcription : 'à café' → 'cuillère à café', 'à soupe' → 'cuillère à soupe', 'oeufs oeufs' → 'œufs'.",
    "   - RÈGLE UNITÉ vs INGRÉDIENT (CRITIQUE) : si tu vois un fragment du type 'à café <X>', 'à soupe <X>', 'cuillère à <X>', 'cas <X>', 'cac <X>', 'pincée <X>' où <X> est un ingrédient, c'est OBLIGATOIREMENT une unité tronquée — JAMAIS un ingrédient. La sortie correcte est : '<quantité si donnée> cuillère à café/soupe de <X>'. Le nom <X> est l'INGRÉDIENT (sel, paprika, huile, cumin), JAMAIS l'unité.",
    "   - Exemples corrects : '1 cuillère à café de sel' (PAS 'à café Sel'), '2 cuillères à soupe d'huile' (PAS 'à soupe Huile'), '1 pincée de paprika' (PAS 'Pincée Paprika').",
    "   - Ne liste PAS d'éléments non comestibles (papier, film, assiette, poêle, spatule).",
    "   - Une seule occurrence par ingrédient.",
    "",
    "4. INGREDIENTS_IMPLIED: ingrédients NON prononcés mais techniquement nécessaires (sel, poivre, huile de cuisson, eau, beurre quand on voit faire revenir, etc.).",
    "   - Format : '- <ingrédient> (probable)'",
    "   - Reste très restrictif : seulement les évidences techniques.",
    "",
    "5. ACTIONS_SEQUENCE: la séquence EXACTE des actions du cuisinier, dans l'ordre, numérotée.",
    "   - Format : '1. <verbe à l'impératif> + <objet> + <détail> [+ durée/température si dits]'",
    "   - Reformule en style culinaire propre, NE recopie JAMAIS une phrase parlée brute.",
    "   - Inclus toutes les phases visibles : préparation, repos, façonnage, cuisson, friture, sauce, assemblage, dressage.",
    "   - Si une phase est techniquement implicite mais clairement nécessaire (ex: préchauffer, laisser reposer la pâte), ajoute-la.",
    "   - Préserve les détails distinctifs : températures, durées, retournements, gestes signature.",
    "",
    "6. SIGNATURE_GESTURES: les gestes ou techniques DISTINCTIFS de cette vidéo qui ne seraient pas dans une recette générique du même plat.",
    "   - Exemples : 'aplatir le steak à la spatule sur la plancha (smash)', 'flamber au cognac', 'griller la baguette au beurre face intérieure', 'caraméliser les oignons 20 minutes', 'panure double œuf-panko'.",
    "   - Format : '- <geste avec son détail spécifique>'",
    "   - Si rien de distinctif, laisse la section vide ('- aucun').",
    "",
    "7. SUB_PREPARATIONS: liste les sous-préparations distinctes de la recette si elles existent (marinade, sauce, pâte, garniture, salade, dressage, montage, cuisson…).",
    "   - Format : '- <Label court> : <ingrédients qui y entrent, séparés par des virgules>'",
    "   - Exemple pour un chicken burger : '- Marinade poulet : blanc de poulet, sauce barbecue, sauce soja sucrée, moutarde, paprika, curcuma, épices mexicaines, persillade, sel, poivre'",
    "   - Si la recette est linéaire (pas de sous-préparations distinctes), écris '- aucun'.",
    "   - Un même ingrédient peut apparaître dans plusieurs sous-préparations (ex: crème fraîche dans Sauce ET Salade).",
    "",
    "8. NOISE_DETECTED: tous les éléments du transcript que tu as délibérément ignorés (pubs, calls-to-action, hors-sujet, bavardage).",
    "   - Liste explicitement : 'abonne-toi', 'like la vidéo', 'lien en bio', 'code promo', 'follow', 'swipe up', 'n'oublie pas de', 'fais-le toi-même', salutations, anecdotes hors-cuisine.",
    "   - Format : '- <fragment ignoré>'",
    "   - Cette section permettra de vérifier qu'aucun de ces fragments ne se retrouvera dans la recette finale.",
    "",
    "RÈGLES STRICTES :",
    "- Ne mélange JAMAIS un élément de NOISE_DETECTED dans une autre section.",
    "- Ne génériscise JAMAIS un nom d'ingrédient prononcé.",
    "- Ne saute aucune section (laisse vide avec '- aucun' si rien à mettre).",
    "",
    "Format de sortie EXACT (texte brut, sans JSON, sans markdown, sans introduction) :",
    "",
    "DISH: <nom complet et précis>",
    "SPECIFICITY: <high|medium|low>",
    "",
    "INGREDIENTS_EXPLICIT:",
    "- <ingrédient 1 avec quantité si donnée>",
    "- <ingrédient 2>",
    "",
    "INGREDIENTS_IMPLIED:",
    "- <ingrédient implicite 1> (probable)",
    "",
    "ACTIONS_SEQUENCE:",
    "1. <action 1>",
    "2. <action 2>",
    "",
    "SIGNATURE_GESTURES:",
    "- <geste distinctif 1>",
    "",
    "SUB_PREPARATIONS:",
    "- <Label 1> : <ingrédient a>, <ingrédient b>",
    "- <Label 2> : <ingrédient c>, <ingrédient d>",
    "",
    "NOISE_DETECTED:",
    "- <fragment ignoré 1>"
  ].filter(Boolean).join("\n");

  const systemPrompt = [
    "Tu es un assistant spécialisé en analyse de transcripts audio de recettes de cuisine en français.",
    "Ton unique rôle est de produire un DIGEST STRUCTURÉ qui sera la source de vérité pour reconstruire la VRAIE recette de la vidéo.",
    "Tu ne rédiges JAMAIS la recette finale, tu produis seulement le digest.",
    "Réponds en texte brut, sans introduction, sans markdown, sans JSON, sans commentaires, en suivant EXACTEMENT le format demandé.",
    "Tu dois corriger silencieusement les erreurs évidentes de reconnaissance vocale française (ex: 'à café' = 'cuillère à café').",
    "PRINCIPE DE FIDÉLITÉ : la vidéo est la source de vérité. Tu n'inventes RIEN, tu ne génériscises RIEN, tu ne supprimes RIEN d'utile.",
    "Tu sépares STRICTEMENT ce qui est explicite (prononcé/montré) de ce qui est implicite (inféré techniquement)."
  ].join("\n");

  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: env.OPENAI_RECIPE_MODEL,
        temperature: 0.1,
        max_output_tokens: 2500,
        input: [
          {
            role: "system",
            content: [{ type: "input_text", text: systemPrompt }]
          },
          {
            role: "user",
            content: [{ type: "input_text", text: userPrompt }]
          }
        ]
      }),
      signal: AbortSignal.timeout(options?.timeoutMs ?? 12_000)
    });

    if (!response.ok) {
      return null;
    }

    const json = await response.json() as Record<string, unknown>;
    const text = resolveOpenAIOutputText(json);
    if (!text) {
      return null;
    }

    const cleaned = text.trim();
    // Loosened from 40 to 30 chars so very short structured digests
    // still get propagated to the normalizer.
    return cleaned.length > 30 ? cleaned : null;
  } catch {
    return null;
  }
}

export async function transcribeMediaFromUrl(
  mediaUrl?: string,
  options?: {
    mediaFetchTimeoutMs?: number;
    transcriptionTimeoutMs?: number;
    maxDurationSeconds?: number;
    maxFileBytes?: number;
    languageHint?: string;
  }
): Promise<string | null> {
  if (!mediaUrl) {
    return null;
  }

  requireProvider("openAI");

  const tempDirectory = await mkdtemp(path.join(os.tmpdir(), "cooksy-media-"));
  const sourcePath = path.join(tempDirectory, "source.bin");
  const audioPath = path.join(tempDirectory, "audio.m4a");
  const maxFileBytes = options?.maxFileBytes ?? 40 * 1024 * 1024;

  try {
    const videoBuffer = await fetchRemoteBuffer(mediaUrl, maxFileBytes, {
      timeoutMs: options?.mediaFetchTimeoutMs
    });
    await fs.writeFile(sourcePath, videoBuffer);
    await extractAudio(sourcePath, audioPath, {
      maxDurationSeconds: options?.maxDurationSeconds
    });

    const audioBuffer = await fs.readFile(audioPath);
    if (audioBuffer.byteLength === 0 || audioBuffer.byteLength > 25 * 1024 * 1024) {
      return null;
    }

    const formData = new FormData();
    formData.append("model", env.OPENAI_TRANSCRIPTION_MODEL);
    formData.append("file", new File([audioBuffer], "cooksy-audio.m4a", { type: "audio/mp4" }));
    if (options?.languageHint) {
      formData.append("language", options.languageHint);
    }
    formData.append(
      "prompt",
      "Transcription d'une vidéo de recette de cuisine en français (parfois mots anglais). RÈGLE STRICTE pour les unités : « cuillère à café » et « cuillère à soupe » se prononcent et s'écrivent EN ENTIER. Tu n'écriras JAMAIS « à café » seul ni « à soupe » seul ; toujours « cuillère à café » ou « cuillère à soupe ». Si tu hésites entre les deux fragments, complète automatiquement avec « cuillère ». Préserve TOUJOURS les quantités exactes prononcées (ex: '300 grammes', 'deux cuillères à soupe', '500 ml', 'une pincée'). Ne dédouble jamais un mot ('œufs œufs' → 'œufs'). Vocabulaire attendu : farine, fécule, levure, eau, sel, sucre, cassonade, œufs, beurre, huile d'olive, huile de tournesol, huile de sésame, ail, oignon, échalote, poulet, bœuf, porc, agneau, poisson, saumon, thon, cabillaud, crevettes, tomate, courgette, aubergine, poivron, champignon, fromage, yaourt, crème, lait, basilic, persil, coriandre, paprika, cumin, curcuma, gingembre, poivre, chapelure, panko, cornflakes, mayonnaise, sauce, épices cajuns, cajun seasoning, Sriracha, gochujang, miso, dashi, mirin, soja, sésame, miel, sirop d'érable, ketchup, moutarde. Plats internationaux : Philly cheesesteak, smash burger, cheeseburger, hoagie, birria, tacos al pastor, quesadilla, enchilada, fajitas, burrito, gyros, shawarma, kebab, falafel, hummus, pita, naan, butter chicken, tikka masala, curry rouge, pad thaï, ramen, pho, bibimbap, kimchi, gyoza, sushi, poke bowl, carbonara, bolognese, lasagne, gnocchi, risotto, focaccia, bruschetta, tiramisu, crêpes, pancakes, gaufres, clafoutis, far breton, financiers, madeleines, chimichurri, tzatziki, tahini, pesto, ratatouille, cassoulet, tartiflette, raclette, croque-monsieur, quiche lorraine, tasty crousty, chicken tenders, chicken nuggets. Pâtes spécifiques : rigatoni, penne, farfalle, tagliatelle, pappardelle, orecchiette, fusilli, casarecce, spaghetti, linguine, conchiglie, macaroni. Fromages spécifiques : provolone, mozzarella, burrata, ricotta, mascarpone, parmesan, pecorino, gorgonzola, gruyère, comté, emmental, reblochon, raclette, brie, camembert, chèvre, feta, halloumi, manchego, cheddar, monterey jack, fromage râpé, fromage à croque. Marques fréquentes : Kiri, Boursin, Philadelphia, Knorr, Maggi, Tabasco, Heinz, Hellmann's, Lay's, Doritos. Coupes de viande : entrecôte, faux-filet, ribeye, picanha, bavette, onglet, paleron, joue de bœuf, jarret, magret, suprême, escalope, blanc de poulet, cuisse de poulet, aiguillette, pavé, tournedos, gigot, carré. Volailles découpées : tenders, nuggets, fillet, aiguillette. Charcuteries : prosciutto, pancetta, chorizo, salami, jambon de Parme, lardons, bacon, guanciale, oignons frits. Mélanges d'épices : cajun seasoning, mélange cajun, garam masala, ras el hanout, herbes de Provence, quatre-épices, mélange italien, paprika fumé, piment d'Espelette, cumin moulu. Sauces et condiments : sauce barbecue, sauce soja, sauce sriracha, sauce yaourt, sauce crémeuse, sauce chili, vinaigre balsamique, jus de citron, persil séché. Unités complètes : cuillère à soupe, cuillère à café, pincée, gramme, kilo, litre, millilitre, tasse, verre. Verbes : préparer, mélanger, ajouter, cuire, faire revenir, pétrir, laisser reposer, étaler, frire, dorer, assaisonner, couper, éplucher, émincer, saler, poivrer, servir, smasher, caraméliser, déglacer, flamber, mariner, paner, glacer, napper, poêler, rôtir, mijoter, blanchir."
    );

    const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.OPENAI_API_KEY}`
      },
      body: formData,
      signal: AbortSignal.timeout(options?.transcriptionTimeoutMs ?? 60_000)
    });

    if (!response.ok) {
      return null;
    }

    const json = await response.json() as { text?: string };
    return json.text?.trim() || null;
  } finally {
    await fs.rm(tempDirectory, { recursive: true, force: true });
  }
}

function buildNormalizationPrompt(input: NormalizerInput): string {
  const structuredDataText = input.pageStructuredData?.length
    ? compactTextBlocks(input.pageStructuredData.slice(0, 2), 2400)
    : "";
  const socialTextBlocks = uniqueStrings([
    input.sharedText,
    input.socialCaption,
    input.socialDescription,
    input.socialPageText,
    input.socialSubtitles
  ]);
  const primarySocialText = socialTextBlocks[0];
  const secondarySocialText = socialTextBlocks[1];
  const tertiarySocialText = socialTextBlocks[2];
  const isSparseSocialText = !primarySocialText || primarySocialText.length < 50;
  const hasDigest = Boolean(input.transcriptDigest && input.transcriptDigest.trim().length > 40);
  const transcriptLabel = hasDigest
    ? "Transcription audio brute (référence secondaire, déjà résumée dans le digest ci-dessus)"
    : isSparseSocialText
      ? "Source principale (audio)"
      : "Transcription audio";

  const audioPrimaryBlock = input.audioIsPrimarySource
    ? [
      "SOURCE AUDIO PRIORITAIRE :",
      "- La bande audio de la vidéo est ta SEULE source fiable. Il n'y a pas (ou très peu) de légende.",
      "- N'invente JAMAIS un ingrédient qui n'est pas prononcé dans la transcription ou clairement déductible d'un geste décrit.",
      "- N'applique JAMAIS un template de plat standard (carbonara, butter chicken, smash burger…) si ses ingrédients-signature ne sont pas dans l'audio.",
      "- Si un fragment audio est mal reconnu (ex: 'à soupe' isolé, 'à café' isolé, 'oeufs oeufs'), corrige-le silencieusement en unité + ingrédient propres ('cuillère à soupe' + nom, dédupliqué).",
      "- Si une quantité ou unité est manquante, laisse le champ vide — ne devine PAS une quantité standard.",
      "- Vérifie que chaque étape ne référence QUE des ingrédients présents dans la liste finale."
    ].join("\n")
    : "";

  // Caption-first mode: the social caption IS a structured recipe and
  // becomes the absolute source of truth for the ingredient list. The
  // audio digest is demoted to step-reconstruction only.
  const captionAuthoritativeBlock = input.captionIsAuthoritative
    ? [
      "★★★ SOURCE PRIORITAIRE = LA LÉGENDE (caption) ★★★",
      "La légende sociale ci-dessous CONTIENT la recette complète et structurée. Elle est ta SOURCE DE VÉRITÉ ABSOLUE pour la liste d'ingrédients.",
      "RÈGLES STRICTES en mode légende-prioritaire :",
      "- La liste d'ingrédients de ta sortie = EXACTEMENT les ingrédients de la légende, avec leurs quantités et unités EXACTES. Tu les recopies, tu ne les recalcules pas.",
      "- Tu n'AJOUTES aucun ingrédient absent de la légende (sauf sel/poivre/eau/huile de cuisson triviaux, marqués `flags.usedInferredIngredients=true`).",
      "- Tu ne SUPPRIMES aucun ingrédient présent dans la légende.",
      "- Tu ne REMPLACES aucun ingrédient de la légende par un autre.",
      "- Les sections de la légende (FILLING / DOUGH / Marinade / Sauce / ⭐ …) deviennent les `group` de chaque ingredientDraft.",
      "- Le DIGEST AUDIO et la transcription servent UNIQUEMENT à reconstruire la SÉQUENCE D'ÉTAPES de cuisson quand la légende n'a pas d'instructions détaillées. JAMAIS pour toucher à la liste d'ingrédients.",
      "- Si la légende n'a pas d'étapes mais que l'audio décrit la préparation, génère les étapes depuis l'audio (`flags.generatedSteps=true`)."
    ].join("\n")
    : "";

  return [
    captionAuthoritativeBlock,
    audioPrimaryBlock,
    `Mode d'import : ${input.mode}`,
    input.sourceUrl ? `URL source : ${input.sourceUrl}` : "",
    input.remoteImageUrl ? `Image distante probable : ${input.remoteImageUrl}` : "",
    input.pageTitle ? `Titre page : ${truncate(input.pageTitle, 180)}` : "",
    input.pageDescription ? `Description page : ${truncate(input.pageDescription, 420)}` : "",
    input.socialTitle ? `Titre social : ${truncate(input.socialTitle, 180)}` : "",
    input.socialAuthor ? `Auteur social : ${truncate(input.socialAuthor, 80)}` : "",
    primarySocialText ? `Texte social principal : ${truncate(primarySocialText, 1800)}` : "",
    secondarySocialText ? `Contexte social secondaire : ${truncate(secondarySocialText, 900)}` : "",
    tertiarySocialText ? `Contexte social additionnel : ${truncate(tertiarySocialText, 700)}` : "",
    hasDigest
      ? (input.captionIsAuthoritative
          ? `Digest audio nettoyé (référence pour la SÉQUENCE D'ÉTAPES uniquement — N'AJOUTE PAS d'ingrédient depuis ce digest, la liste vient de la légende) :\n${truncate(input.transcriptDigest!.trim(), 2200)}`
          : `Digest audio nettoyé (SOURCE PRIORITAIRE pour plat, ingrédients et séquence d'étapes) :\n${truncate(input.transcriptDigest!.trim(), 2200)}`)
      : "",
    input.transcript ? `${transcriptLabel} : ${truncate(input.transcript, 2600)}` : "",
    input.pageTextContent ? `Texte web / sources : ${truncate(input.pageTextContent, 2200)}` : "",
    structuredDataText ? `Données structurées : ${structuredDataText}` : "",
    [
      "Consignes opérationnelles (le system prompt définit la stratégie de fidélité, ces consignes sont de l'opérationnel) :",
      input.captionIsAuthoritative
        ? "- MODE LÉGENDE-PRIORITAIRE ACTIF : la LÉGENDE est ta source de vérité pour les ingrédients (recopie-les tous, quantités exactes). Le digest audio ne sert QU'À reconstruire les étapes de cuisson."
        : "- Si le digest audio structuré est présent dans le contexte, c'est ta SOURCE DE VÉRITÉ : applique la VALIDATION FINALE FID-1 à FID-8.",
      "- Si le digest est absent, exploite directement la transcription audio brute, puis la légende, puis les sources web. Même hiérarchie de fidélité.",
      "- GROUPEMENT : si le digest contient SUB_PREPARATIONS avec ≥2 entrées, tu DOIS reproduire ce groupement via le champ `group` de chaque ingredientDraft ET via le champ `section` de la première étape de chaque groupe. Les labels de `group` et `section` doivent matcher exactement.",
      "- Si le digest n'a pas de SUB_PREPARATIONS mais que la légende ou les étapes révèlent clairement des sous-préparations (ex: mots-clés 'marinade:', 'sauce:', 'pour la salade', 'pour le montage'), tu DOIS quand même grouper.",
      "- Préserve toujours les ingrédients spécifiques nommés (provolone, panko, gochujang, ribeye, burrata, Kiri…) — ne les remplace JAMAIS par des génériques.",
      "- nutritionQuery = nom court en anglais USDA.",
      "- searchQuery = requête courte exploitable basée sur le nom de plat précis + ingrédients distinctifs (ex: 'philly cheesesteak provolone hoagie'), pas juste 'sandwich'.",
      "- Pour tout contenu culinaire, fournis toujours calories, protéines, glucides et lipides cohérents avec les ingrédients finaux.",
      "- Pas de timestamps, flèches '-->', URLs, hashtags, boutons, pubs, 'Read More', 'View post', 'abonne-toi', 'lien en bio' dans le titre/ingrédients/étapes.",
      "- Si tu déduis un ingrédient ou une quantité absente, signale-le brièvement dans notesText.",
      "- Si le titre reste générique malgré le contexte, mets needsWebFallback=true et formule un searchQuery riche."
    ].join("\n")
  ]
    .filter(Boolean)
    .join("\n\n");
}

function buildCookabilityReviewPrompt(
  draft: RecipeImportResult,
  context: NormalizerInput,
  reviewHint?: string
): string {
  const hintBlock = reviewHint?.trim()
    ? [`INSTRUCTION PRIORITAIRE :`, reviewHint.trim(), ""]
    : [];
  return [
    ...hintBlock,
    "Recette structurée actuelle :",
    JSON.stringify(draft, null, 2),
    "",
    "Contexte source :",
    buildNormalizationPrompt(context),
    "",
    "Checklist obligatoire :",
    "- Vérifie si la recette est réellement faisable du début à la fin.",
    "- Vérifie qu'aucun ingredientDraft ne contient plusieurs ingrédients fusionnés; si c'est le cas, sépare-les.",
    "- Si des ingrédients essentiels manquent, ajoute-les quand ils sont clairement implicites dans le titre, la légende, la transcription, les données structurées ou l'image.",
    "- Si plusieurs sources web sont présentes, compare-les et garde la version la plus cohérente entre elles.",
    "- N'imite jamais le ton parlé de la vidéo et ne recopie pas ses phrases : transforme en vraie méthode de recette.",
    "- Si des étapes essentielles manquent, ajoute-les dans le bon ordre pour qu'un client puisse vraiment cuisiner le plat.",
    "- Supprime tout texte social, CTA, hashtags, commentaires, timestamps et formulations inutiles.",
    "- Si tu fais une déduction raisonnable, note-le brièvement dans notesText.",
    "- Vérifie que calories, protéines, glucides et lipides restent cohérents entre eux ; corrige plutôt que renvoyer une nutrition vide.",
    "",
    "CHECKLIST FIDÉLITÉ VIDÉO (en plus de la cookabilité — applique-la si un digest audio structuré est présent dans le contexte) :",
    "",
    "1. Compare `title` aux champs DISH et SIGNATURE_GESTURES du digest. Si le titre est plus générique que ce que le digest permettait (ex: titre = 'Sandwich' alors que DISH = 'Philly cheesesteak'), REMPLACE-LE par le DISH précis.",
    "",
    "2. Pour chaque entrée de INGREDIENTS_EXPLICIT du digest, vérifie qu'elle est dans `ingredientDrafts` avec son nom EXACT. Si 'provolone' est dans le digest et 'fromage' est dans la recette, CORRIGE en 'provolone'. Pareil pour 'panko'/'chapelure', 'ribeye'/'bœuf', 'gochujang'/'sauce piquante', 'baguette à hoagie'/'pain', 'burrata'/'mozzarella', 'Kiri'/'fromage frais'.",
    "",
    "3. Vérifie que la séquence `stepDrafts` respecte l'ordre de ACTIONS_SEQUENCE. Réordonne si nécessaire.",
    "",
    "4. Vérifie que tous les SIGNATURE_GESTURES sont présents dans une étape avec leur détail. Sinon, ajoute les étapes manquantes dans le bon ordre.",
    "",
    "5. Supprime de title/ingredientDrafts/stepDrafts/notesText tout terme listé dans NOISE_DETECTED qui aurait fui dans la recette ('abonne-toi', 'lien en bio', 'code promo', etc.).",
    "",
    "6. Le titre n'est jamais un mot de catégorie seul (sandwich, burger, pizza, pasta, salade, tacos, wrap, bowl, curry, ramen, gratin, quiche, omelette). S'il l'est, recompose un titre précis depuis DISH ou les ingrédients distinctifs.",
    "",
    "7. Si après corrections la recette est toujours plus générique que le digest et que tu ne peux pas la corriger toi-même, mets `confidence='low'`, `needsWebFallback=true` et fournis un `searchQuery` précis basé sur DISH + 2-3 ingrédients distinctifs.",
    "",
    "VÉRIFICATION DES MOTS SUSPECTS (applique universellement, pas seulement avec digest) :",
    "- Pour CHAQUE ingredientDraft, si le champ `name` contient un fragment d'unité au début ('à soupe', 'à café', 'cuillère', 'pincée', 'gramme', 'grammes', 'piece') : CORRIGE en déplaçant l'unité dans le champ `unit` et en gardant uniquement le nom propre de l'ingrédient dans `name`. Ne laisse JAMAIS 'À soupe huile' ou 'À café sel' dans le nom final.",
    "- Pour CHAQUE ingredientDraft, si le champ `name` contient un mot dupliqué consécutif (ex: 'Oeufs Oeufs', 'Farine farine', 'Huile huile') : dédoublonne immédiatement.",
    "- Si un ingrédient est présent qui ne peut pas raisonnablement appartenir au plat détecté (ex: poulet ou pâtes dans une recette de crêpes sucrées, thon dans un gâteau au chocolat, sucre dans une pizza savoyarde), et qu'il n'est ni dans le digest ni dans la transcription ni dans la légende : SUPPRIME-LE.",
    "- Pour CHAQUE étape, si son texte mentionne un ingrédient ('poulet', 'pâtes', 'ail', 'crème', 'farine', 'beurre', 'sucre', 'fromage', etc.) qui n'est PAS dans la liste finale d'ingrédients : soit tu ajoutes l'ingrédient manquant à la liste si le digest/transcription le confirme, soit tu reformules l'étape pour retirer la référence fantôme.",
    "- Vérifie que chaque ingredientDraft.name commence par une lettre d'alphabet (pas par un nombre, pas par 'à', pas par 'de', pas par 'du')."
  ].join("\n");
}

async function requestStructuredRecipeFromOpenAI(input: {
  userPrompt: string;
  imageDataUrl?: string;
  timeoutMs?: number;
  systemInstructions: string[];
}): Promise<RecipeImportResult> {
  const contents: Array<Record<string, string>> = [
    {
      type: "input_text",
      text: input.userPrompt
    }
  ];

  if (input.imageDataUrl) {
    contents.push({
      type: "input_image",
      image_url: input.imageDataUrl
    });
  }

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${env.OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: env.OPENAI_RECIPE_MODEL,
      temperature: 0.2,
      max_output_tokens: 4000,
      input: [
        {
          role: "system",
          content: [
            {
              type: "input_text",
              text: input.systemInstructions.join("\n")
            }
          ]
        },
        {
          role: "user",
          content: contents
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "cooksy_recipe_import",
          schema: recipeJsonSchema,
          strict: true
        }
      }
    }),
    signal: AbortSignal.timeout(input.timeoutMs ?? 60_000)
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`OpenAI normalization failed (${response.status}): ${errorBody}`);
  }

  const json = await response.json() as Record<string, unknown>;
  const outputText = resolveOpenAIOutputText(json);
  if (!outputText) {
    console.error(
      "[openAIService] Unexpected OpenAI response structure:",
      JSON.stringify(json).slice(0, 800)
    );
    throw new Error("OpenAI normalization returned an empty output_text payload.");
  }

  const parsed = recipeImportSchema.parse(JSON.parse(outputText));
  return sanitizeRecipeImport(parsed);
}

// Concurrency gate for ffmpeg transcodes.
//
// Each transcribed import writes ~40 MB of video + ~25 MB of decoded
// audio to /tmp and spawns a ffmpeg process. Unbounded concurrency on
// a single Railway instance (~512 MB – 8 GB RAM depending on plan)
// risks OOM when many imports land at once. Cap at 4 in-flight
// transcodes and queue the rest — the average ffmpeg run completes
// in 2–6 s so the queue drains quickly. Surplus callers simply await
// their slot instead of failing.
const FFMPEG_MAX_CONCURRENCY = 4;
let ffmpegInFlight = 0;
const ffmpegWaiters: Array<() => void> = [];

async function acquireFfmpegSlot(): Promise<void> {
  if (ffmpegInFlight < FFMPEG_MAX_CONCURRENCY) {
    ffmpegInFlight += 1;
    return;
  }
  await new Promise<void>((resolve) => {
    ffmpegWaiters.push(() => {
      ffmpegInFlight += 1;
      resolve();
    });
  });
}

function releaseFfmpegSlot(): void {
  ffmpegInFlight -= 1;
  const next = ffmpegWaiters.shift();
  if (next) next();
}

async function extractAudio(
  sourcePath: string,
  destinationPath: string,
  options?: {
    maxDurationSeconds?: number;
  }
): Promise<void> {
  if (!ffmpegPath) {
    throw new Error("ffmpeg-static is not available.");
  }

  await acquireFfmpegSlot();
  try {
    await execFileAsync(ffmpegPath, [
      "-y",
      "-i",
      sourcePath,
      "-vn",
      "-ac",
      "1",
      "-ar",
      "16000",
      "-t",
      String(options?.maxDurationSeconds ?? 300),
      "-c:a",
      "aac",
      "-b:a",
      "96k",
      destinationPath
    ]);
  } finally {
    releaseFfmpegSlot();
  }
}

async function resolveNormalizationImageDataUrl(
  input: Pick<NormalizerInput, "imageDataUrl" | "remoteImageUrl">,
  timeoutMs?: number
): Promise<string | undefined> {
  if (input.imageDataUrl?.trim()) {
    return input.imageDataUrl;
  }

  if (!input.remoteImageUrl?.trim()) {
    return undefined;
  }

  const imageTimeoutMs = boundedImageFetchTimeout(timeoutMs);
  if (!imageTimeoutMs) {
    return undefined;
  }

  try {
    const payload = await fetchRemoteFile(input.remoteImageUrl, 5 * 1024 * 1024, {
      timeoutMs: imageTimeoutMs
    });
    const mimeType = normalizedImageMimeType(payload.contentType, input.remoteImageUrl);
    if (!mimeType) {
      return undefined;
    }

    return `data:${mimeType};base64,${payload.buffer.toString("base64")}`;
  } catch {
    return undefined;
  }
}

function boundedImageFetchTimeout(timeoutMs?: number): number | undefined {
  if (!timeoutMs) {
    return 4_000;
  }

  if (timeoutMs < 3_500) {
    return undefined;
  }

  return Math.max(1_500, Math.min(4_000, Math.floor(timeoutMs * 0.2)));
}

function normalizedImageMimeType(contentType?: string, url?: string): string | undefined {
  const rawType = contentType?.split(";")[0]?.trim().toLowerCase();
  if (rawType?.startsWith("image/")) {
    return rawType;
  }

  const lowercaseUrl = url?.toLowerCase() ?? "";
  if (lowercaseUrl.includes(".png")) {
    return "image/png";
  }
  if (lowercaseUrl.includes(".webp")) {
    return "image/webp";
  }
  if (lowercaseUrl.includes(".gif")) {
    return "image/gif";
  }
  if (lowercaseUrl.includes(".heic") || lowercaseUrl.includes(".heif")) {
    return "image/heic";
  }
  if (lowercaseUrl.includes(".avif")) {
    return "image/avif";
  }

  return "image/jpeg";
}

function resolveOpenAIOutputText(json: Record<string, unknown>): string | undefined {
  // Top-level convenience property (most common)
  if (typeof json.output_text === "string" && json.output_text.trim()) {
    return json.output_text.trim();
  }

  // Nested structure: output[].content[].text
  if (Array.isArray(json.output)) {
    for (const outputItem of json.output) {
      if (!outputItem || typeof outputItem !== "object") {
        continue;
      }

      const item = outputItem as Record<string, unknown>;

      // Direct text on output item
      if (typeof item.text === "string" && item.text.trim()) {
        return item.text.trim();
      }

      // Nested content array
      if (Array.isArray(item.content)) {
        for (const contentItem of item.content) {
          if (!contentItem || typeof contentItem !== "object") {
            continue;
          }

          const content = contentItem as Record<string, unknown>;
          if (typeof content.text === "string" && content.text.trim()) {
            return content.text.trim();
          }
        }
      }
    }
  }

  return undefined;
}
