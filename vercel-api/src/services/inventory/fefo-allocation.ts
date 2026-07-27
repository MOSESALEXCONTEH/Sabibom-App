import {daysRemainingForBusiness} from "./product-intelligence";

export type FefoBatchStatus = "active" | "depleted" | "expired" | "voided";

export interface FefoBatchInput {
  id: string;
  quantityRemaining: number;
  unitCostMinor: number;
  expiryDateKnown: boolean;
  expiryDate: string | null;
  status: FefoBatchStatus;
}

export interface FefoAllocation {
  batchId: string;
  quantity: number;
  unitCostMinor: number;
  expiryDate: string | null;
  lineCostMinor: number;
}

export class InsufficientStockError extends Error {
  constructor(message = "Insufficient stock to allocate requested quantity.") {
    super(message);
    this.name = "InsufficientStockError";
  }
}

/**
 * Pure FEFO allocator: earliest known expiry first, unknown-expiry last.
 * Skips depleted/voided/expired batches (status or daysRemaining < 0).
 */
export function allocateFefo(input: {
  requestedQty: number;
  batches: FefoBatchInput[];
  timezone?: string;
  now?: Date;
}): FefoAllocation[] {
  const requestedQty = input.requestedQty;
  if (!Number.isFinite(requestedQty) || requestedQty <= 0) {
    throw new Error("Requested quantity must be greater than zero.");
  }

  const eligible = sortBatchesForFefo(
    input.batches.filter((batch) =>
      isBatchEligibleForSale(batch, {
        timezone: input.timezone,
        now: input.now,
      }),
    ),
  );

  const allocations: FefoAllocation[] = [];
  let remaining = requestedQty;

  for (const batch of eligible) {
    if (remaining <= 0) break;
    const take = Math.min(batch.quantityRemaining, remaining);
    if (take <= 0) continue;
    allocations.push({
      batchId: batch.id,
      quantity: take,
      unitCostMinor: batch.unitCostMinor,
      expiryDate:
        batch.expiryDateKnown && batch.expiryDate ? batch.expiryDate : null,
      lineCostMinor: Math.round(take * batch.unitCostMinor),
    });
    remaining -= take;
  }

  if (remaining > 1e-9) {
    throw new InsufficientStockError(
      `Not enough saleable stock. Short by ${roundQty(remaining)}.`,
    );
  }

  return allocations;
}

export function isBatchEligibleForSale(
  batch: FefoBatchInput,
  options?: {timezone?: string; now?: Date},
): boolean {
  if (
    batch.status === "depleted" ||
    batch.status === "voided" ||
    batch.status === "expired"
  ) {
    return false;
  }
  if (!Number.isFinite(batch.quantityRemaining) || batch.quantityRemaining <= 0) {
    return false;
  }
  if (batch.expiryDateKnown && batch.expiryDate) {
    const days = daysRemainingForBusiness({
      expiryDate: batch.expiryDate,
      timezone: options?.timezone,
      now: options?.now,
    });
    if (days < 0) return false;
  }
  return true;
}

export function sortBatchesForFefo(batches: FefoBatchInput[]): FefoBatchInput[] {
  return [...batches].sort((left, right) => {
    const leftKnown = left.expiryDateKnown && Boolean(left.expiryDate);
    const rightKnown = right.expiryDateKnown && Boolean(right.expiryDate);
    if (leftKnown && rightKnown) {
      const byDate = String(left.expiryDate).localeCompare(
        String(right.expiryDate),
      );
      if (byDate !== 0) return byDate;
      return left.id.localeCompare(right.id);
    }
    if (leftKnown && !rightKnown) return -1;
    if (!leftKnown && rightKnown) return 1;
    return left.id.localeCompare(right.id);
  });
}

export function costOfGoodsSoldFromAllocations(
  allocations: FefoAllocation[],
): number {
  return allocations.reduce((sum, row) => sum + row.lineCostMinor, 0);
}

export function weightedUnitCostMinor(
  allocations: FefoAllocation[],
  quantity: number,
): number {
  if (!Number.isFinite(quantity) || quantity <= 0) return 0;
  return Math.round(costOfGoodsSoldFromAllocations(allocations) / quantity);
}

function roundQty(value: number): number {
  return Math.round(value * 1_000_000) / 1_000_000;
}
