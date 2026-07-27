export const EXPIRY_STATUSES = [
  "not_tracked",
  "safe",
  "expiring_soon",
  "expires_today",
  "expired",
  "mixed",
] as const;

export type ExpiryStatus = (typeof EXPIRY_STATUSES)[number];

export function lineValueMinor(quantity: number, unitMinor: number): number {
  if (!Number.isFinite(quantity) || quantity <= 0) return 0;
  return Math.round(quantity * unitMinor);
}

export function calculatePotentialProfit(input: {
  quantity: number;
  unitCostMinor: number;
  sellingPriceMinor: number;
}) {
  const stockCostValueMinor = lineValueMinor(
    input.quantity,
    input.unitCostMinor,
  );
  const expectedStockRevenueMinor = lineValueMinor(
    input.quantity,
    input.sellingPriceMinor,
  );
  return {
    unitPotentialProfitMinor:
      input.sellingPriceMinor - input.unitCostMinor,
    stockCostValueMinor,
    expectedStockRevenueMinor,
    potentialProfitRemainingMinor:
      expectedStockRevenueMinor - stockCostValueMinor,
  };
}

export function daysRemainingForBusiness(input: {
  expiryDate: string;
  now?: Date;
  timezone?: string;
}): number {
  const expiry = parseDateOnly(input.expiryDate);
  const now = input.now ?? new Date();
  const today = businessDateParts(now, input.timezone ?? "Africa/Freetown");
  const todayUtc = Date.UTC(today.year, today.month - 1, today.day);
  const expiryUtc = Date.UTC(expiry.year, expiry.month - 1, expiry.day);
  return Math.round((expiryUtc - todayUtc) / 86_400_000);
}

export function expiryStatusForDate(input: {
  expiryDate: string;
  reminderThresholdDays?: number;
  now?: Date;
  timezone?: string;
}): ExpiryStatus {
  const remaining = daysRemainingForBusiness(input);
  if (remaining < 0) return "expired";
  if (remaining === 0) return "expires_today";
  if (remaining <= (input.reminderThresholdDays ?? 30)) {
    return "expiring_soon";
  }
  return "safe";
}

function parseDateOnly(value: string): {
  year: number;
  month: number;
  day: number;
} {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) throw new Error("Invalid date-only value.");
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new Error("Invalid date-only value.");
  }
  return {year, month, day};
}

function businessDateParts(
  value: Date,
  timezone: string,
): {year: number; month: number; day: number} {
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(value);
    const read = (type: string) =>
      Number(parts.find((part) => part.type === type)?.value);
    return {year: read("year"), month: read("month"), day: read("day")};
  } catch {
    return {
      year: value.getUTCFullYear(),
      month: value.getUTCMonth() + 1,
      day: value.getUTCDate(),
    };
  }
}
