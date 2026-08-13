# Google Play Data Safety Worksheet

This worksheet reflects the current code. Reconcile it with the exact Google Play form wording at submission time.

## General declarations

- Data is encrypted in transit: Yes
- Users can request deletion: Yes, in app and at `https://sabibom.com/delete-account`
- Data is sold: No
- Data is processed for advertising: No current advertising SDK or ad feature found
- Account creation: Yes

## Data types to disclose

| Play category | Examples in SabiBom | Purpose | Shared with service provider |
|---|---|---|---|
| Name | Account, customer, supplier and staff names | Account and app functionality | Firebase/Vercel infrastructure |
| Email address | Sign-in, staff invitations, support, deletion verification | Account, security and support | Firebase/Auth providers |
| Phone number | Profile, customer and supplier contact details | App functionality | Cloud infrastructure |
| User IDs | Firebase UID, business membership identifiers | Account, permissions, security | Firebase/Vercel |
| Photos | Profile/business images, expense or feedback attachments | User-selected functionality | Storage infrastructure |
| Voice or sound recordings | Microphone input converted to text for Sabi | App functionality | Speech/AI service when invoked |
| Financial information | Sales, purchases, expenses, balances, prices and reports | Core business functionality | Firebase/Vercel |
| App interactions | Feature use and analytics events | Analytics and product improvement | Firebase Analytics |
| Crash logs | Crash diagnostics | Reliability and security | Firebase Crashlytics |
| Diagnostics | Performance and request diagnostics | Reliability | Firebase Performance/Vercel |
| Device or other IDs | Installation/device tokens and App Check data | Push, security and fraud prevention | Firebase Messaging/App Check |
| Files and documents | Receipts, PDFs, backups and selected attachments | App functionality | Cloud/file infrastructure |

## Permission explanations

- Notifications: deliver low-stock, expiry, operational and platform notifications.
- Camera: capture business/profile/expense images and supported barcode or document workflows.
- Microphone: optional voice input for Sabi.
- Audio settings: support speech capture behavior.

## Submission checks

- [ ] Confirm Firebase Analytics, Crashlytics and Performance collection behavior in the release build
- [ ] Confirm every third-party AI/file provider currently enabled in production
- [ ] Confirm no advertising SDK has been introduced
- [ ] Confirm push payloads contain no sensitive transaction detail
- [ ] Confirm the public deletion URL and in-app deletion route work
- [ ] Confirm privacy-policy wording matches the final form
