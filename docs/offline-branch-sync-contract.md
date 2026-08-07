# Offline Branch Sync Contract

No durable offline transaction queue was present in the supplied SabiBom source. This document defines the required contract for the future queue; it does not claim offline branch writes are implemented.

Every queued branch-owned mutation must capture these immutable values when the user creates it:

```text
operationId
businessId
branchId
recordType
recordId
payload
createdAt
createdBy
syncStatus
attemptCount
```

Rules:

1. `branchId` must be a real active branch ID; `all` and `all_branches` are invalid.
2. Sync must use the queued `branchId`, never the branch currently selected in the UI.
3. Before writing, the backend must re-check that the branch belongs to the business, is active, and remains accessible to the user.
4. A branch that became inactive must produce a safe conflict state; the operation must not move to Main Branch automatically.
5. Switching from East Branch to West Branch must not change queued East Branch operations.
6. The queue must not silently replace missing branch IDs. Legacy queue entries require a reviewed migration.
7. Retry must be idempotent and preserve the same operation ID and branch ID.

Recommended conflict statuses:

```text
branch_missing
branch_inactive
branch_access_revoked
business_mismatch
manual_review_required
```
