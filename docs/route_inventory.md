# Route Inventory

Generated for Phase 12 from `lib/app/router.dart`. Update when routes change.

| Path | Route name | Permission (typical) | Source | Back / notes | Deep link |
|------|------------|----------------------|--------|--------------|-----------|
| `/` | (splash) | — | App start | → onboarding/home | No |
| `/onboarding` | — | guest | Splash | Login/Register | No |
| `/login` | — | guest | Onboarding | Home after auth | No |
| `/register` | — | guest | Onboarding | Setup choice | No |
| `/business-setup-choice` | — | signed-in | Auth | Setup / Home | No |
| `/business-setup` | — | signed-in | Choice | Home | No |
| `/business-profile` | — | member | More | pop | No |
| `/home` | `home` | member | Shell | — | Yes |
| `/sales` | `sales` | sales view | Shell | — | Yes |
| `/sales/new` | `newSale` | `create_sale` | Sales | pop | No |
| `/sales/checkout` | `checkout` | `create_sale` | New sale | pop | No |
| `/sales/:saleId` | `saleDetails` | sale view | History | pop | Yes |
| `/products` | `products` | `view_products` | Shell | — | Yes |
| `/products/new` | `newProduct` | `manage_products` | Products | pop | No |
| `/products/:id` | `productDetails` | `view_products` | List/notif | pop | Yes |
| `/customers` | `customers` | `view_customers` | Shell | — | Yes |
| `/customers/:id` | `customerDetails` | `view_customers` | List/notif | pop | Yes |
| `/more` | `more` | member | Shell | — | Yes |
| `/settings` | `settings` | member | More | pop | No |
| `/settings/notifications` | `settingsNotifications` | prefs | More/Notif | pop | No |
| `/settings/release-readiness` | `releaseReadiness` | owner/dev | Settings | pop | No |
| `/notifications` | — | `view_notifications` | Bell | pop | Yes |
| `/reports` | `reports` | reports | More | pop | Yes |
| `/reports/daily-summary/:dateKey` | `dailySummary` | `view_daily_summary` | Notif | pop | Yes |
| `/reports/weekly/:weekKey` | `weeklyReport` | `view_weekly_report` | Notif | pop | Yes |
| `/reports/end-of-day/:dateKey` | `endOfDay` | `view_end_of_day_alerts` | More/Reports/Notif | pop | Yes |
| `/backup` | `backup` | `edit_business_settings` | More/Setup | pop | Yes |
| `/team` | `team` | `manage_staff` | More | pop | Yes |
| `/approvals` | `approvals` | approvals | More | pop | Yes |
| `/approvals/:id` | `approvalDetails` | approvals | Notif | pop | Yes |
| `/help` | `help` | signed-in | More | pop | No |
| `/help/faq` | `helpFaq` | signed-in | Help | pop | No |
| `/help/feedback` | `helpFeedback` | signed-in | Help | pop | No |
| `/help/contact` | `helpContact` | signed-in | Help | pop | No |
| `/help/report-problem` | `helpReportProblem` | signed-in | Help | pop | No |
| `/about` | `about` | signed-in | More | pop | No |
| `/access-denied` | — | — | Guards | Home | No |
| `/expenses` … | expenses* | expenses | More | pop | Partial |
| `/suppliers` … | suppliers* | suppliers | More | pop | Partial |
| `/purchases` … | purchases* | purchases | More | pop | Partial |
| `/invite` | `invite` | signed-in | Deep invite | Home | Yes |

## Navigator keys
Declared once in `router.dart`: `root`, `home`, `sales`, `products`, `customers`, `more`. Do not recreate in `build()`.

## Access rules
- Permission failure → Access Denied (not Page Not Found).
- Missing entity → friendly “no longer available”.
- Notification routes must use allowlisted `routeName` values.
