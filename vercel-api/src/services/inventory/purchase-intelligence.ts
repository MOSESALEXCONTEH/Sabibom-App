import {expiryStatusForDate, type ExpiryStatus} from "./product-intelligence";

export type DiscountType = "fixed" | "percentage";

export interface PurchaseCalculationItem {
  quantity: number;
  unitCostMinor: number;
  discountType?: DiscountType | null;
  discountValue?: number;
}

export interface PurchaseTotals {
  subtotalMinor: number;
  itemDiscountMinor: number;
  orderDiscountMinor: number;
  taxMinor: number;
  deliveryMinor: number;
  totalMinor: number;
  amountPaidMinor: number;
  balanceDueMinor: number;
}

export interface InventoryBatchSummaryInput {
  id: string;
  quantityRemaining: number;
  unitCostMinor: number;
  expiryDate?: string | null;
  expiryDateKnown: boolean;
  status: "active" | "depleted" | "expired" | "voided";
}

export interface InventoryBatchSummary {
  expiryStatus: ExpiryStatus;
  nextExpiryDate: string | null;
  nextExpiryBatchId: string | null;
  nextExpiryBatchQuantity: number;
  expiringQuantity: number;
  expiredQuantity: number;
  unknownExpiryQuantity: number;
  stockCostValueMinor: number;
  expectedStockRevenueMinor: number;
  potentialProfitRemainingMinor: number;
}

export function lineSubtotalMinor(item: PurchaseCalculationItem): number {
  validatePurchaseItem(item);
  return Math.round(item.quantity * item.unitCostMinor);
}

export function lineDiscountMinor(item: PurchaseCalculationItem): number {
  return calculateDiscount(
    lineSubtotalMinor(item),
    item.discountType,
    item.discountValue ?? 0,
  );
}

export function calculatePurchaseTotals(input: {
  items: PurchaseCalculationItem[];
  orderDiscountType?: DiscountType | null;
  orderDiscountValue?: number;
  taxPercentage?: number;
  deliveryMinor?: number;
  amountPaidMinor?: number;
}): PurchaseTotals {
  const taxPercentage = input.taxPercentage ?? 0;
  const deliveryMinor = input.deliveryMinor ?? 0;
  const amountPaidMinor = input.amountPaidMinor ?? 0;
  if (
    !Number.isFinite(taxPercentage) ||
    taxPercentage < 0 ||
    taxPercentage > 100
  ) {
    throw new Error("Tax percentage must be between 0 and 100.");
  }
  if (deliveryMinor < 0 || amountPaidMinor < 0) {
    throw new Error("Delivery and amount paid cannot be negative.");
  }

  const subtotalMinor = input.items.reduce(
    (sum, item) => sum + lineSubtotalMinor(item),
    0,
  );
  const itemDiscountMinor = input.items.reduce(
    (sum, item) => sum + lineDiscountMinor(item),
    0,
  );
  const afterItems = Math.max(0, subtotalMinor - itemDiscountMinor);
  const orderDiscountMinor = calculateDiscount(
    afterItems,
    input.orderDiscountType,
    input.orderDiscountValue ?? 0,
  );
  const taxable = Math.max(0, afterItems - orderDiscountMinor);
  const taxMinor = Math.round(taxable * (taxPercentage / 100));
  const totalMinor = Math.max(0, taxable + taxMinor + deliveryMinor);
  const paid = Math.min(amountPaidMinor, totalMinor);
  return {
    subtotalMinor,
    itemDiscountMinor,
    orderDiscountMinor,
    taxMinor,
    deliveryMinor,
    totalMinor,
    amountPaidMinor: paid,
    balanceDueMinor: Math.max(0, totalMinor - paid),
  };
}

export function summarizeInventoryBatches(input: {
  tracksExpiry: boolean;
  batches: InventoryBatchSummaryInput[];
  sellingPriceMinor: number;
  timezone: string;
  reminderThresholdDays?: number;
  now?: Date;
}): InventoryBatchSummary {
  const remaining = input.batches.filter(
    (batch) =>
      Number.isFinite(batch.quantityRemaining) &&
      batch.quantityRemaining > 0 &&
      batch.status !== "depleted" &&
      batch.status !== "voided",
  );
  let stockCostValueMinor = 0;
  let totalQuantity = 0;
  for (const batch of remaining) {
    stockCostValueMinor += Math.round(
      batch.quantityRemaining * batch.unitCostMinor,
    );
    totalQuantity += batch.quantityRemaining;
  }
  const expectedStockRevenueMinor = Math.round(
    totalQuantity * input.sellingPriceMinor,
  );

  if (!input.tracksExpiry) {
    return {
      expiryStatus: "not_tracked",
      nextExpiryDate: null,
      nextExpiryBatchId: null,
      nextExpiryBatchQuantity: 0,
      expiringQuantity: 0,
      expiredQuantity: 0,
      unknownExpiryQuantity: 0,
      stockCostValueMinor,
      expectedStockRevenueMinor,
      potentialProfitRemainingMinor:
        expectedStockRevenueMinor - stockCostValueMinor,
    };
  }

  const known: Array<{
    batch: InventoryBatchSummaryInput;
    expiryDate: string;
    status: ExpiryStatus;
  }> = [];
  let unknownExpiryQuantity = 0;
  for (const batch of remaining) {
    if (!batch.expiryDateKnown || !batch.expiryDate) {
      unknownExpiryQuantity += batch.quantityRemaining;
      continue;
    }
    known.push({
      batch,
      expiryDate: batch.expiryDate,
      status: expiryStatusForDate({
        expiryDate: batch.expiryDate,
        reminderThresholdDays: input.reminderThresholdDays ?? 30,
        timezone: input.timezone,
        now: input.now,
      }),
    });
  }
  known.sort((left, right) =>
    left.expiryDate.localeCompare(right.expiryDate),
  );

  let expiringQuantity = 0;
  let expiredQuantity = 0;
  const statuses = new Set<ExpiryStatus>();
  for (const entry of known) {
    statuses.add(entry.status);
    if (
      entry.status === "expiring_soon" ||
      entry.status === "expires_today"
    ) {
      expiringQuantity += entry.batch.quantityRemaining;
    } else if (entry.status === "expired") {
      expiredQuantity += entry.batch.quantityRemaining;
    }
  }
  const next = known[0];
  const expiryStatus =
    statuses.size > 1
      ? "mixed"
      : (statuses.values().next().value as ExpiryStatus | undefined) ?? "safe";
  return {
    expiryStatus,
    nextExpiryDate: next?.expiryDate ?? null,
    nextExpiryBatchId: next?.batch.id ?? null,
    nextExpiryBatchQuantity: next?.batch.quantityRemaining ?? 0,
    expiringQuantity,
    expiredQuantity,
    unknownExpiryQuantity,
    stockCostValueMinor,
    expectedStockRevenueMinor,
    potentialProfitRemainingMinor:
      expectedStockRevenueMinor - stockCostValueMinor,
  };
}

function validatePurchaseItem(item: PurchaseCalculationItem): void {
  if (!Number.isFinite(item.quantity) || item.quantity <= 0) {
    throw new Error("Each purchase quantity must be greater than zero.");
  }
  if (!Number.isInteger(item.unitCostMinor) || item.unitCostMinor < 0) {
    throw new Error("Unit cost cannot be negative.");
  }
  const value = item.discountValue ?? 0;
  if (!Number.isFinite(value)) {
    throw new Error("Discount must be a valid number.");
  }
  if (
    item.discountType === "percentage" &&
    (value < 0 || value > 100)
  ) {
    throw new Error("Percentage discount must be between 0 and 100.");
  }
}

function calculateDiscount(
  subtotal: number,
  type: DiscountType | null | undefined,
  value: number,
): number {
  if (!type || value <= 0) return 0;
  if (!Number.isFinite(value)) {
    throw new Error("Discount must be a valid number.");
  }
  if (type === "percentage" && value > 100) {
    throw new Error("Percentage discount must be between 0 and 100.");
  }
  const discount =
    type === "fixed"
      ? Math.round(value * 100)
      : Math.round(subtotal * (value / 100));
  return Math.min(subtotal, Math.max(0, discount));
}
