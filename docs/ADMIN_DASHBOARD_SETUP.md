# SabiBom Super Admin Dashboard — Checkpoint 1 Setup

Separate Next.js app for platform administrators only (`admin-dashboard/`).
Domain target later: `admin.sabibom.com`.

## Prerequisites

- Node.js 20+
- Firebase project `sabibom-app`
- Service account with Admin SDK access (same style as `vercel-api`)
- An **existing** Firebase Authentication user for the first Super Admin
  (email/password or Google). The bootstrap script never creates passwords.

## Environment variables

Copy `.env.example` to `.env.local` and fill values (never commit secrets).

### Client (public)

- `NEXT_PUBLIC_FIREBASE_API_KEY`
- `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`
- `NEXT_PUBLIC_FIREBASE_PROJECT_ID`
- `NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET`
- `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID`
- `NEXT_PUBLIC_FIREBASE_APP_ID`
- `NEXT_PUBLIC_APP_ENV` (`development` | `staging` | `production`)

### Server (private — Admin SDK)

- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY` (escape newlines as `\n`)
- `ADMIN_SESSION_COOKIE_NAME` (optional, default `__sabibom_admin_session`)
- `ADMIN_SESSION_EXPIRES_DAYS` (optional, default `5`, max `14`)
- `ADMIN_ENFORCE_MFA` (optional; set `true` later when MFA enrollment is ready)

### Bootstrap only (remove after first run)

- `BOOTSTRAP_SUPER_ADMIN_EMAIL` — existing Auth user email
- `BOOTSTRAP_ALLOW=true` — required safety latch
- `BOOTSTRAP_FORCE=true` — dangerous; only to overwrite a non-super_admin doc

## Install and run locally

```bash
cd admin-dashboard
npm install
npm run typecheck
npm test
npm run dev
```

App listens on http://localhost:3100

## Bootstrap the first Super Admin (one time)

1. Ensure the person already has a Firebase Auth user (Console → Authentication).
2. In `.env.local` (or your shell) set:

```bash
BOOTSTRAP_ALLOW=true
BOOTSTRAP_SUPER_ADMIN_EMAIL=your-existing-admin@example.com
```

3. Run:

```bash
npm run bootstrap:super-admin
```

4. Expected success line:

```text
BOOTSTRAP_OK status=created uid=<uid>
```

Re-running when the doc is already `super_admin` + `active` is idempotent:

```text
BOOTSTRAP_OK status=already_active_super_admin uid=<uid>
```

5. **Disable bootstrap configuration immediately:**

- Remove `BOOTSTRAP_ALLOW`
- Remove `BOOTSTRAP_SUPER_ADMIN_EMAIL`
- Remove `BOOTSTRAP_FORCE` if set
- Do not add the bootstrap script to CI or production deploy hooks

6. Sign in at `/login` with that account. Ordinary SabiBom users without a
   `platform_admins/{uid}` document are sent to `/unauthorized`.

## Security model (Checkpoint 1)

1. Firebase Authentication (client)
2. ID token verified with Admin SDK (`POST /api/admin/session`)
3. `platform_admins/{uid}` must exist and `status === active`
4. HTTP-only session cookie (Secure in production, SameSite=Lax)
5. Middleware + server layout + API helpers enforce session
6. Permissions resolved from role defaults (browser role claims are ignored)

Firestore collections (server-only via Admin SDK):

- `platform_admins/{uid}`
- `platform_admin_activity/{activityId}`

Client Firestore rules deny all access to these collections.

## MFA foundation

`mfaRequired` is stored on the admin document. When true, the shell shows a
setup banner. Full Firebase MFA enrollment enforcement is deferred; set
`ADMIN_ENFORCE_MFA=true` only after Console MFA is configured.

## Firebase Console checklist

- Enable Email/Password and Google providers (same as mobile app)
- Authorized domains include localhost and later `admin.sabibom.com`
- Create service account key for Admin SDK (store only in Vercel/server env)
- Deploy updated `firestore.rules` from the monorepo root

## Deploy notes

- Host as a separate Vercel project pointing at `admin-dashboard/`
- Do not auto-deploy production from this checkpoint
- Never put `FIREBASE_PRIVATE_KEY` in `NEXT_PUBLIC_*` variables

## Out of scope until later checkpoints

Metrics, users/businesses CRUD, feedback, AI monitoring, ops jobs, billing UI.
