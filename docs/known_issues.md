# Known Issues

Classification: **P0** release blocker · **P1** critical · **P2** high · **P3** medium · **P4** low

Last updated: 2026-07-22  
Build under review: `0.1.0+1` (`com.sabibom.app`)

## Open issues

| ID | Pri | Feature | Summary | Workaround | Status |
|----|-----|---------|---------|------------|--------|
| KI-004 | P2 | Push notifications | Server push needs deployed Vercel FCM + cron auth | Rely on in-app notifications until device push verified | Open |
| KI-005 | P3 | Large-data | 1k+ entity stress not yet measured on low-RAM phones | Paginate; avoid production seed | Open |
| KI-006 | P3 | Accessibility | Full TalkBack pass pending on physical devices | Use labels/tooltips already present on key screens | Open |
| KI-007 | P3 | Backup restore picker | Restore currently uses recent local exports on-device; picking an arbitrary file from Downloads needs a follow-up file picker | Share backup into the app documents flow or re-export | Open |

## Fixed / shipped since Phase 12 incomplete list

| ID | Summary |
|----|---------|
| KI-001 | End-of-Day cash-up screen (draft/finalize/reopen/PDF) + routes + rules |
| KI-002 | Backup export/share + restore-as-new-business |
| KI-003 | Weekly report aggregation (vs prior week, top products, EOD counts) |
| KI-F04 | Feedback screenshot upload via Pinata `feedback_attachment` |

## Fixed in Phase 12 (track regression)

| ID | Summary |
|----|---------|
| KI-F01 | Onboarding completion now persisted via `OnboardingService` |
| KI-F02 | About screen shows live version/build via `package_info_plus` |
| KI-F03 | Setup checklist + demo mode + help/feedback added |

## Deferred

See `docs/future_roadmap.md`.
