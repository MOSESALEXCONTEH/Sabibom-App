# Firebase Console setup (Super Admin Dashboard)

## Project

- Firebase project: `sabibom-app`
- Dashboard domain target: `admin.sabibom.com`
- Local: `http://localhost:3100`

## Authentication

1. Enable **Email/Password** and **Google** (same providers as the mobile app).
2. Authorized domains:
   - `localhost`
   - `admin.sabibom.com` (when DNS/Vercel are ready)
3. Do **not** bootstrap admins by hardcoding emails in client code.
4. Platform authorization uses Firestore `platform_admins/{uid}` + verified session cookies.

## MFA (foundation)

1. In Firebase Console → Authentication → Sign-in method, enable MFA (SMS and/or TOTP as appropriate).
2. Keep `ADMIN_ENFORCE_MFA` unset/`false` until enrollment UX is verified in staging.
3. Set `mfaRequired: true` on sensitive admin docs (`super_admin`, `security_admin`).
4. Sensitive operations call `requireRecentAuthentication()` server-side.

Do not build custom OTP schemes.

## Admin SDK service account

1. Create/use a service account with Firebase Admin privileges.
2. Store only on the server / Vercel project for `admin-dashboard`:
   - `FIREBASE_PROJECT_ID`
   - `FIREBASE_CLIENT_EMAIL`
   - `FIREBASE_PRIVATE_KEY`
3. Never put these in `NEXT_PUBLIC_*` or the Flutter app.

## Firestore rules

Deploy monorepo `firestore.rules` so platform collections remain Admin-SDK-only.
`platform_settings/public` may be readable by signed-in clients for maintenance /
minimum-version fields only.

## First Super Admin bootstrap

1. Create the Auth user in Console (email/password or Google) — do not invent passwords in scripts.
2. In `admin-dashboard/.env.local` set:
   - `BOOTSTRAP_ALLOW=true`
   - `BOOTSTRAP_SUPER_ADMIN_EMAIL=<existing-auth-email>`
3. Run `npm run bootstrap:super-admin`
4. Immediately remove bootstrap env vars.
5. Sign in at `/login`.

## App Check / security notes

- Prefer App Check on mobile APIs (`vercel-api`).
- Admin dashboard uses session cookies + permission checks + audit logs.
- Ordinary business owners are never platform admins by default.
