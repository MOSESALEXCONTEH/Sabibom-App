# Branch Inventory Migration

This migration moves legacy single-location stock into the new authoritative branch inventory path:

```text
businesses/{businessId}/branches/main/inventory/{productId}
```

It also labels existing branch-owned records that have no `branchId` as Main Branch records. It does **not** run automatically.

## Before running

1. Deploy and verify the Phase 3 code in a non-production Firebase project.
2. Export or otherwise back up production Firestore.
3. Confirm every business should use `main` as its legacy branch ID.
4. Confirm the Vercel API project has its existing server-only Firebase Admin environment variables.
5. Run the dry-run and review all counts.

## Dry-run

From `vercel-api`:

```powershell
node scripts/migrate-branch-inventory.cjs
```

Dry-run is the default. It performs reads only and prints safe aggregate counts.

## Apply

Only after approving the dry-run:

```powershell
node scripts/migrate-branch-inventory.cjs --apply
```

The script:

- creates a missing `Main Branch` document;
- creates missing Main Branch inventory documents from legacy product stock;
- skips inventory documents already present;
- adds `branchId: main` only to branchless records;
- processes writes in bounded batches;
- is idempotent and may be re-run after a partial failure.

## Collections covered

The utility uses collections present in the supplied project:

- products → Main Branch inventory
- sales
- expenses
- purchases
- purchase_returns
- inventory_batches
- inventory_movements
- activity
- analytics
- supplier_payments
- customer ledger entries
- supplier ledger entries

Product definitions and customer identities remain business-level.

## Verification

After applying, verify:

1. Every business has exactly one active `branches/main` document.
2. Each legacy product has a Main Branch inventory document.
3. Main Branch totals match the legacy product quantities.
4. Existing records with a real `branchId` were unchanged.
5. East/West branch views do not show legacy branchless records.
6. All Branches reports include Main Branch legacy records.
7. A sale reduces only its selected branch inventory.
8. A sale void restores stock to the same branch.
9. A purchase adds stock only to its selected branch.

## Rollback limitations

The script only adds branch metadata and branch inventory documents; it does not delete legacy product quantity fields. Those aggregate fields are retained as a compatibility mirror. A rollback can delete migration-created branch inventory documents and remove `branchId` fields only from records positively identified by `branchMigratedAt`, but this should be done with a separately reviewed script after restoring from backup where possible.
