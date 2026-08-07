# Data Safety Validation

| Check | Status |
|-------|--------|
| Users see only their businesses | Rules + membership — retest |
| Staff profit/cost hidden when restricted | Permission system — retest |
| Notifications user-specific | `users/{uid}/notifications` |
| Demo data isolated (`isDemo: true`) | Implemented |
| Feedback has no auto customer PII | Safe diagnostics only |
| Push payloads minimal | Vercel push service sanitizes |
| Logs without secrets | Do not print env values |
| Disabled staff lose access | Retest Journey F |

Fill after closed testing.
