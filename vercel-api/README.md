# SabiBom API (Vercel)

Secure Node.js functions for:

- `GET /api/health`
- `POST /api/sabi/parse-receipt`
- `POST /api/sabi/business-question`
- `POST /api/pinata/upload-url`

Secrets stay on Vercel. Flutter only sends Firebase ID tokens.

## Setup

```bash
cd vercel-api
npm install
cp .env.example .env.local
# Fill .env.local locally — never commit values
npm run typecheck
npm test
npx vercel dev
```

## Vercel project settings

- Root Directory: `vercel-api`
- Framework Preset: Other
- Install Command: `npm ci` or `npm install`
- Runtime: Node.js (not Edge)

## Environment variables

Set in Vercel Dashboard → Settings → Environment Variables:

- `GROQ_API_KEY`
- `GROQ_MODEL`
- `PINATA_JWT`
- `PINATA_GATEWAY`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`
- `ALLOWED_ORIGINS`
- `APP_ENV`

Redeploy after changing variables.

## Flutter

```bash
flutter run --dart-define=SABIBOM_API_BASE_URL=https://YOUR-PROJECT.vercel.app
```

For a physical Android phone against local `vercel dev`, use your computer LAN IP (not `localhost`).
