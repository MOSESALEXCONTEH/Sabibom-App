# Test Coverage Report

Build: `0.1.0+1` · Updated: 2026-07-22

| Feature | Test type | Covered | Missing / notes | Status |
|---------|-----------|---------|-----------------|--------|
| Notification model | Unit | Parse, priority, allowlist | Widget centre filters | Pass |
| Business summary helpers | Unit | percentChange, date keys | Full daily generate integration | Pass |
| Financial validation | Unit | Single sale, discount, partial pay, format | Tax-inclusive matrix, EOD cash, concurrent stock | Partial |
| Team permissions | Unit (existing) | Role defaults | Firestore rules emulator suite | Partial |
| Profit calculator | Unit (existing) | COGS/profit | Missing cost snapshot cases | Partial |
| Sales draft navigation | Unit (existing) | Sabi draft routes | — | Pass |
| Setup checklist | — | — | Widget + completion rules | Missing |
| Demo isolation | — | — | Create/reset/isolation | Missing |
| Feedback | — | — | Validation + no secrets | Missing |
| Integration E2E | — | — | Device journeys A–K | Pending device |
| Firestore rules | Manual / deploy | — | Emulator suite | Missing |
| Backend endpoints | — | — | Auth/cron rejection | Partial |

**Principle:** Prefer high-risk money and permission tests over coverage percentage.
