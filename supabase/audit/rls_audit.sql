-- ─────────────────────────────────────────────────────────────────────
-- RLS Pre-Launch Audit — Cooksy
--
-- Lance ce script dans le SQL Editor de Supabase (Production).
-- L'objectif : confirmer que TOUTES les tables publiques ont RLS active
-- avant le lancement public. Une seule ligne dans le résultat de la
-- requête #1 = vulnérabilité critique (donnée lisible/écrivable par
-- n'importe quel JWT signé via la clé anon).
-- ─────────────────────────────────────────────────────────────────────


-- 1) Tables sans RLS — DOIT renvoyer 0 ligne.
--    Toute ligne ici représente une fuite directe : un client iOS
--    avec son JWT user peut lire / écrire la table sans contrôle.
SELECT
    schemaname,
    tablename,
    rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = false
ORDER BY tablename;


-- 2) Tables RLS-on mais SANS policy — DOIT renvoyer 0 ligne.
--    Une table avec RLS activée mais zéro policy bloque TOUT (y compris
--    les lectures légitimes côté iOS). Cela casse l'app au lieu de la
--    sécuriser — donc on veut explicitement zéro résultat.
SELECT
    t.tablename,
    t.rowsecurity,
    COUNT(p.policyname) AS policy_count
FROM pg_tables t
LEFT JOIN pg_policies p
    ON p.schemaname = t.schemaname
   AND p.tablename = t.tablename
WHERE t.schemaname = 'public'
  AND t.rowsecurity = true
GROUP BY t.tablename, t.rowsecurity
HAVING COUNT(p.policyname) = 0
ORDER BY t.tablename;


-- 3) Inventaire de TOUTES les policies (à relire à la main).
--    Vérifie en particulier :
--      • `profiles` : un utilisateur ne doit pouvoir écrire QUE sa
--        propre ligne, et JAMAIS la colonne `is_premium` (gérée par
--        le webhook RevenueCat via service_role).
--      • `import_quota_window` : SELECT-own uniquement, écriture via
--        la RPC `consume_import_quota` (security definer).
--      • `webhook_events` : aucune policy pour `anon` ou
--        `authenticated` — service_role only.
--      • `recipes`, `meal_plans`, `shopping_lists` : SELECT/INSERT/
--        UPDATE/DELETE filtrés par `user_id = auth.uid()`.
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, cmd, policyname;


-- 4) Permissions accordées au rôle `anon` — point d'attaque côté JWT.
--    DOIT renvoyer uniquement les tables que l'app iOS lit en
--    pré-auth (ex: rien aujourd'hui — tout passe par `authenticated`).
SELECT
    table_schema,
    table_name,
    privilege_type,
    grantee
FROM information_schema.role_table_grants
WHERE grantee = 'anon'
  AND table_schema = 'public'
ORDER BY table_name, privilege_type;


-- 5) Functions / RPCs accessibles à `anon` ou `authenticated` —
--    chacune doit être conçue pour être appelable sans danger.
--    Notamment : `consume_import_quota` doit refuser les appels où
--    le user_id ne matche pas `auth.uid()`.
SELECT
    n.nspname AS schema,
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS args,
    r.rolname AS granted_to
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_authid r ON has_function_privilege(r.rolname, p.oid, 'EXECUTE')
WHERE n.nspname = 'public'
  AND r.rolname IN ('anon', 'authenticated')
ORDER BY function_name, granted_to;
