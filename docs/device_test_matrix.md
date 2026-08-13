# Physical Android Release Acceptance

Record date, tester, device model, Android version, build number, result and evidence for every row.

| Environment | Required workflows | Result |
|---|---|---|
| Small/medium physical phone | Install release build, sign up, sign in, remember-me behavior, business setup, sign out | Pending |
| Owner account | Create Main and East branches; verify branch-isolated sales, purchases, expenses, customers and stock | Pending |
| Staff account | Assigned branch appears; other branch data and owner-only reports remain inaccessible | Pending |
| Sales | Complete cash and credit sales, receipt preview/share/PDF, insufficient-stock handling, duplicate-submit prevention | Pending |
| Inventory | Add product with opening stock, stock in/out/opening balance, low-stock and expiry alerts | Pending |
| Operations | Purchases, suppliers, expenses, customer payments and balances | Pending |
| Notifications | Permission allowed/denied; foreground/background/terminated push; in-app notification route | Pending |
| Sabi | Text, malformed intent, follow-up answer, microphone denied/allowed, copy/edit, fresh chat | Pending |
| Reliability | Airplane mode, reconnect, slow network, interrupted save and visible sync state | Pending |
| Accessibility | Large font, TalkBack, dark mode, keyboard, no overflow on compact screen | Pending |
| Account controls | Password/social login, profile update, deletion submission and status | Pending |
| Release bundle | Play internal-test install, Play Integrity/App Check, Crashlytics nonfatal test | Pending |

## Acceptance rule

No P0/P1 defects. Financial and branch-isolation journeys must pass twice without stale or cross-branch data. Any failed save must be visible and recoverable without duplicate records.
