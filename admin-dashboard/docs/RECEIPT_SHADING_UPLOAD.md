# Receipt Shading Upload

Upload local shading images to Firebase Storage and register them in Firestore for the app shading picker.

## Prerequisites

Set these environment variables (same as other admin scripts):

- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

## Default source folder

If you run from `admin-dashboard`, the script reads from:

- `../assets/Shading background`

## Run

```bash
UPLOAD_ALLOW=true npm run upload:receipt-shadings
```

## Optional overrides

- `SHADING_SOURCE_DIR`: custom local folder path
- `SHADING_STORAGE_PREFIX`: custom storage prefix (default: `receipt_shading/backgrounds`)

Example:

```bash
UPLOAD_ALLOW=true SHADING_SOURCE_DIR="../assets/Shading background" SHADING_STORAGE_PREFIX="receipt_shading/backgrounds" npm run upload:receipt-shadings
```

## What it writes

Collection: `receipt_shading_backgrounds`

Each document includes:

- `name`
- `storagePath`
- `imageUrl`
- `thumbnailUrl`
- `isActive`
- `isPremium`
- `sortOrder`
- `updatedAt`

The mobile app will use `imageUrl` when available, otherwise it resolves from `storagePath` via Firebase Storage.
