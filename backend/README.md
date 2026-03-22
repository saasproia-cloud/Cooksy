# Cooksy Backend

Backend Node.js + TypeScript pour l'import social public, l'analyse photo/texte, la reconstruction de recettes et l'enrichissement visuel de la liste de courses.

## Variables d'environnement

Copiez `.env.example` vers `.env` puis remplacez uniquement les placeholders :

```bash
cp .env.example .env
```

Variables requises :

- `OPENAI_API_KEY`
- `APIFY_TOKEN`
- `SERPAPI_KEY`
- `BACKEND_BASE_URL`
- `APP_ENV`

Notes de déploiement Railway :

- `BACKEND_BASE_URL` doit être une URL publique complète, par exemple `https://cooksy-production-7309.up.railway.app`
- si vous utilisez `RAILWAY_PUBLIC_DOMAIN`, le backend normalise automatiquement la valeur vers `https://...`
- le backend cible Node `22.x` en production

## Démarrage local

```bash
npm install
npm run doctor
npm run dev
```

Le serveur démarre par défaut sur `http://localhost:3000`.

## Endpoints

- `GET /health`
- `POST /api/import/url`
- `POST /api/import/text`
- `POST /api/import/photo`
- `POST /api/shopping/enrich`

## Railway

1. Créez un nouveau service Railway depuis le dossier `backend/`.
2. Ajoutez les variables d'environnement de `.env.example` dans l'onglet `Variables`.
3. Déployez : Railway utilisera `railway.json`.
4. Récupérez l'URL publique Railway et remplacez `BACKEND_BASE_URL` côté app iOS.
