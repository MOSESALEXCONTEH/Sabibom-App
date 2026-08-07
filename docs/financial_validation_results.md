# Financial Validation Results

| # | Scenario | Expected | Result | Notes |
|---|----------|----------|--------|-------|
| 1 | Single-item sale | Subtotal = qty × price | Unit test | Pass (suite) |
| 2 | Multi-item sale | Sum of lines | Pending | Expand suite |
| 3 | Decimal quantity | Rounded minor units | Pending | If supported |
| 4 | Fixed discount | Total reduced by fixed | Pending | |
| 5 | Percentage discount | 10% of 10000 = 9000 | Unit test | Pass |
| 6–7 | Tax inclusive/exclusive | Match tax settings | Pending | Device |
| 8 | Partial payment | Balance due correct | Unit test | Pass |
| 9 | Credit sale | Balance to customer | Pending | Device Journey E |
| 10 | Mixed payments | — | Pending | |
| 11–13 | Customer payment / void / refund | Ledger reverse | Pending | Device |
| 14–15 | Expense create/void | Reports reverse | Pending | Device |
| 16–18 | Purchase / pay / return | Stock + debt | Pending | Device |
| 19–21 | COGS / gross / net | ProfitCalculator | Existing tests | Partial |
| 22 | Missing cost snapshot | profitIsEstimated | Existing | Partial |
| 23–25 | EOD cash / shortage / surplus | — | **Blocked KI-001** | |
| 26–27 | Currency / rounding | formatCurrency safe | Unit test | Pass |
| 28–30 | Large / zero / negative | No NaN | Unit test | Pass |
| 31–32 | Duplicate / concurrent | Idempotent writes | Pending | Device |

**AI must not validate financial results.**  
**Overall:** Partial — unit suite started; full matrix requires device + EOD completion.
