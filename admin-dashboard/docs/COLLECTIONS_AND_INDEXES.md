# Platform collections and indexes

All platform-admin collections are **server-only** via Firebase Admin SDK.
Firestore rules deny client `read`/`write` except `platform_settings/public`
(signed-in read of safe public fields only).

## Collections

| Collection | Purpose |
|---|---|
| `platform_admins` | Platform administrator records (`uid` doc id) |
| `platform_admin_activity` | Admin audit log |
| `platform_metrics_daily` | Precomputed daily aggregates |
| `platform_settings` | `public`, `general`, `ai`, `system_health`, `release_readiness` |
| `platform_feature_flags` | Feature flags |
| `platform_announcements` | Announcements |
| `platform_app_versions` | App version / release records |
| `platform_ai_requests` | Safe AI request metadata (hashed ids, no prompts) |
| `platform_security_events` | Security / auth / App Check / rate-limit events |
| `platform_backup_jobs` | Backup job metadata |
| `platform_restore_jobs` | Restore job metadata |
| `platform_import_jobs` | Import job metadata |
| `platform_deletion_requests` | Account / business deletion requests |
| `platform_notifications` | Admin-initiated notification batches |
| `platform_beta_testers` | Closed-beta tester registry |
| `platform_scheduled_jobs` | Scheduled job health metadata |
| `support_tickets` | Support tickets |
| `bug_reports` | Bug reports |
| `subscription_plans` | Draft subscription plans (no payments) |
| `business_subscriptions` | Business subscription foundation |
| `billing_events` | Billing event ledger foundation |

Shared product collections (read via Admin SDK, carefully):

- `users`, `businesses`, `feedback`, `sabi_unanswered`

## Suggested composite indexes

Create in Firebase Console (or `firestore.indexes.json`) as queries are used:

1. `platform_admins`: `role` ASC + `status` ASC
2. `platform_admin_activity`: `createdAt` DESC
3. `platform_metrics_daily`: `dateKey` DESC
4. `support_tickets`: `status` ASC + `createdAt` DESC
5. `bug_reports`: `status` ASC + `priority` ASC + `createdAt` DESC
6. `platform_ai_requests`: `status` ASC + `createdAt` DESC
7. `platform_backup_jobs`: `status` ASC + `createdAt` DESC
8. `platform_deletion_requests`: `status` ASC + `createdAt` DESC
9. `platform_feature_flags`: `updatedAt` DESC
10. `platform_app_versions`: `status` ASC + `releasedAt` DESC
11. `platform_announcements`: `status` ASC + `createdAt` DESC
12. `platform_security_events`: `category` ASC + `createdAt` DESC
13. `platform_beta_testers`: `status` ASC + `joinedAt` DESC
14. `businesses`: `status` ASC + `name` ASC
15. `feedback`: `status` ASC + `createdAt` DESC

## Data minimization

Do not store in platform collections:

- Passwords, ID tokens, refresh tokens
- Full FCM device tokens
- API keys / provider secrets
- Full private AI prompts or financial line items by default
- Unredacted backup package contents
