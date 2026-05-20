-- ============================================================================
-- Cooksy — Notifications v1 template seed
-- ----------------------------------------------------------------------------
-- Seeds the 19 templates that ship in the MVP v1. See the plan file:
--   /Users/youssef/.claude/plans/glimmering-tickling-moth.md
-- for the full rationale, segments, timing windows, and frequency caps.
--
-- All copy is FR-first, tutoiement, ≤40 chars title / ≤120 chars body so it
-- renders fully on every iPhone banner since iPhone X.
--
-- Re-run safe: ON CONFLICT (id) DO UPDATE so we can tweak copy in-place.
-- ============================================================================

insert into public.notification_templates (
  id, category, priority, is_marketing, is_active,
  title_fr, body_fr, deep_link, variables, cooldown_days
) values

-- A. Onboarding & Activation -------------------------------------------------

('welcome_d0', 'onboarding', 1, false, true,
 'Prêt à transformer ta 1ère vidéo ?',
 'Colle un lien TikTok ou Insta — recette propre en 30 secondes.',
 'cooksy://import',
 '[]'::jsonb, 0),

('first_import_celebrate', 'onboarding', 1, false, true,
 'Ta première recette est prête 👨‍🍳',
 'Ouvre-la avant de cuisiner — étapes, ingrédients, tout y est.',
 'cooksy://recipe/{recipe_id}',
 '["recipe_id"]'::jsonb, 0),

('import_silence_d2', 'onboarding', 1, true, true,
 'On t''attend en cuisine 🍝',
 'Essaie un Reel que tu as sauvegardé — on en fait une recette claire.',
 'cooksy://import',
 '[]'::jsonb, 30),

('import_5_milestone', 'milestone', 2, true, true,
 '5 recettes, déjà 🎉',
 'Tu prends le rythme. Voilà ton organiseur de la semaine.',
 'cooksy://library',
 '[]'::jsonb, 0),

-- B. Conversion Free → Premium ----------------------------------------------

('quota_reached_immediate', 'quota', 0, true, true,
 'Imports illimités — 7 jours offerts',
 'Continue sans limite, annule à tout moment avant la fin de l''essai.',
 'cooksy://paywall?source=quota_push',
 '[]'::jsonb, 7),

('quota_reached_d1_followup', 'quota', 1, true, true,
 'Ton quota se réinitialise dans {days_until_reset} jours',
 'Ou débloque tout maintenant — 7 jours gratuits sur l''annuel.',
 'cooksy://paywall?source=quota_d1',
 '["days_until_reset"]'::jsonb, 7),

('quota_reset_anticipation', 'quota', 2, true, true,
 'Ton quota repart à zéro demain 🔄',
 '5 nouveaux imports à venir. Ou passe en illimité avant la fin.',
 'cooksy://paywall?source=quota_reset',
 '[]'::jsonb, 6),

('weekend_meal_prep_free', 'premium', 2, true, true,
 'Et si on prévoyait la semaine ?',
 'Plan de repas + liste de courses auto. 7 jours offerts.',
 'cooksy://paywall?source=meal_prep',
 '[]'::jsonb, 7),

-- C. Trial 7 jours ----------------------------------------------------------

('trial_started_welcome', 'trial', 1, false, true,
 'Premium débloqué pour 7 jours 🔓',
 'Plonge dans nutrition, plan de repas et mode guidé. Aucun paiement.',
 'cooksy://home',
 '[]'::jsonb, 0),

('trial_d5_reminder', 'trial', 1, false, true,
 'Plus que 2 jours d''essai',
 'Ton premium continue automatiquement le {trial_end_date}. Aucune action requise.',
 'cooksy://profile/subscription',
 '["trial_end_date"]'::jsonb, 0),

('trial_d6_morning', 'trial', 1, false, true,
 'Demain, ton premium continue',
 'Pas convaincu ? Annule depuis Réglages avant ce soir.',
 'cooksy://profile/subscription',
 '[]'::jsonb, 0),

('trial_d6_evening_value_recap', 'trial', 1, false, true,
 'Ta semaine en chiffres 📊',
 '{import_count} recettes importées, {cook_count} étapes guidées. Garde tout pour {annual_price}/an.',
 'cooksy://home',
 '["import_count", "cook_count", "annual_price"]'::jsonb, 0),

-- D. Premium actif — rétention ----------------------------------------------

('welcome_paid_d0', 'premium', 2, false, true,
 'Merci d''être avec nous ❤️',
 'Ton premium continue. Ouvre Cooksy, on a remis l''accès illimité.',
 'cooksy://home',
 '[]'::jsonb, 0),

-- E. Premium dormant / churn risk -------------------------------------------

('cancelled_renewal_save_d0', 'premium', 1, false, true,
 'Tu gardes tout jusqu''au {expiration_date}',
 'Profite des derniers jours. Si tu changes d''avis : un tap suffit.',
 'cooksy://profile/subscription',
 '["expiration_date"]'::jsonb, 0),

('cancelled_renewal_save_d_minus_3', 'premium', 1, false, true,
 '3 jours avant la fin de ton premium',
 'Réactive en 1 tap, sans repasser par le paywall.',
 'cooksy://profile/subscription',
 '[]'::jsonb, 0),

-- F. Réactivation (dormants free) -------------------------------------------

('dormant_d7', 'dormant', 2, true, true,
 'Un nouveau Reel à transformer ?',
 'On a accéléré l''extraction. Test un lien, tu verras.',
 'cooksy://import',
 '[]'::jsonb, 30),

('dormant_d30_offer', 'dormant', 2, true, true,
 '7 jours offerts pour revenir',
 'Reprends Cooksy avec tout débloqué. Annulable n''importe quand.',
 'cooksy://paywall?source=dormant_30',
 '[]'::jsonb, 90),

-- G. Win-back (premium expiré) ----------------------------------------------

('lapsed_d7_value', 'lapsed', 1, true, true,
 'Ton illimité te manque ?',
 'Reprends là où tu t''es arrêté. Sans frais d''activation, sans engagement.',
 'cooksy://paywall?source=lapsed_d7',
 '[]'::jsonb, 14),

-- H. Cadeau / promo (urgence) -----------------------------------------------

('gift_expires_6h', 'gift', 1, true, true,
 'Plus que 6h pour ton −25 % 🎁',
 'Ton cadeau expire ce soir. Annulable à tout moment après.',
 'cooksy://paywall?gift=1',
 '[]'::jsonb, 0)

on conflict (id) do update set
  category           = excluded.category,
  priority           = excluded.priority,
  is_marketing       = excluded.is_marketing,
  is_active          = excluded.is_active,
  title_fr           = excluded.title_fr,
  body_fr            = excluded.body_fr,
  deep_link          = excluded.deep_link,
  variables          = excluded.variables,
  cooldown_days      = excluded.cooldown_days,
  version            = public.notification_templates.version + 1,
  updated_at         = now();
