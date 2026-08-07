# End-to-End Test Plan

Platform: Android (`com.sabibom.app`)  
Currency: SLE / Le · Timezone: Africa/Freetown

Mark each step: Pass / Fail / Blocked · Device · Build · Tester · Date

## Journey A — New user
1. Install → open → create account → auth state OK  
2. Create first business → profile → logo → currency/timezone  
3. Dashboard loads with active business  

## Journey B — First sale
1. Add product (sell + cost) → add stock → add customer  
2. Create sale → payment → complete  
3. Stock decreases · history updates · receipt PDF download/share  
4. Sale details totals match  

## Journey C — Expense
1. Category → expense (+ optional image) → reports update  
2. Void expense → totals reverse  

## Journey D — Supplier / purchase
1. Supplier → purchase → partial payment → stock up · balance up  
2. Supplier payment → ledger  
3. Purchase return → stock/debt reverse  

## Journey E — Customer credit
1. Credit sale → balance → statement → partial → final → zero  

## Journey F — Staff
1. Invite → accept → Cashier (sales yes, profit no)  
2. Manager role update · disable · restore  

## Journey G — End of Day
1. Cash + Mobile Money sales · cash expense · supplier cash payment  
2. Expected cash rules · opening/counted · balanced / shortage / surplus  
3. Finalize · PDF · reopen (if permitted)  
**Note:** Treat as Blocked if EOD screen incomplete (KI-001).

## Journey H — Notifications
1. Low stock once · no duplicate on refresh · replenish · re-trigger new cycle  
2. Route · badge · mark-all-read  

## Journey I — Sabi
1. Sale draft only → confirm · expense draft · today’s profit deterministic  
2. Cashier profit denied · provider failure safe fallback  

## Journey J — Backup / recovery
**Blocked** until backup ships (KI-002). Skip for beta stage 1 if not advertised.

## Journey K — Imports
1. Products/customers/suppliers CSV · mapping · invalid rows · no dupes on re-import  
**Blocked** if import UI not present — document as missing.

## Sign-off
Primary tester: ________ Device: ________ Build: ________ Date: ________
