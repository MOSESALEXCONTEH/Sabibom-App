import {describe, expect, it} from "vitest";
import {
  allocateFefo,
  InsufficientStockError,
  sortBatchesForFefo,
  type FefoBatchInput,
} from "../src/services/inventory/fefo-allocation";

const now = new Date("2026-07-22T12:00:00.000Z");
const timezone = "Africa/Freetown";

function batch(
  partial: Partial<FefoBatchInput> & Pick<FefoBatchInput, "id">,
): FefoBatchInput {
  return {
    quantityRemaining: 10,
    unitCostMinor: 100,
    expiryDateKnown: false,
    expiryDate: null,
    status: "active",
    ...partial,
  };
}

describe("allocateFefo", () => {
  it("allocates earliest known expiry first", () => {
    const allocations = allocateFefo({
      requestedQty: 3,
      timezone,
      now,
      batches: [
        batch({
          id: "late",
          quantityRemaining: 10,
          unitCostMinor: 200,
          expiryDateKnown: true,
          expiryDate: "2026-12-01",
        }),
        batch({
          id: "early",
          quantityRemaining: 10,
          unitCostMinor: 150,
          expiryDateKnown: true,
          expiryDate: "2026-08-01",
        }),
      ],
    });

    expect(allocations).toEqual([
      {
        batchId: "early",
        quantity: 3,
        unitCostMinor: 150,
        expiryDate: "2026-08-01",
        lineCostMinor: 450,
      },
    ]);
  });

  it("spans two batches when the first is insufficient", () => {
    const allocations = allocateFefo({
      requestedQty: 7,
      timezone,
      now,
      batches: [
        batch({
          id: "a",
          quantityRemaining: 4,
          unitCostMinor: 100,
          expiryDateKnown: true,
          expiryDate: "2026-08-01",
        }),
        batch({
          id: "b",
          quantityRemaining: 10,
          unitCostMinor: 120,
          expiryDateKnown: true,
          expiryDate: "2026-09-01",
        }),
      ],
    });

    expect(allocations).toEqual([
      {
        batchId: "a",
        quantity: 4,
        unitCostMinor: 100,
        expiryDate: "2026-08-01",
        lineCostMinor: 400,
      },
      {
        batchId: "b",
        quantity: 3,
        unitCostMinor: 120,
        expiryDate: "2026-09-01",
        lineCostMinor: 360,
      },
    ]);
  });

  it("places unknown-expiry batches last", () => {
    const ordered = sortBatchesForFefo([
      batch({
        id: "unknown",
        expiryDateKnown: false,
        expiryDate: null,
      }),
      batch({
        id: "known",
        expiryDateKnown: true,
        expiryDate: "2026-10-01",
      }),
    ]);
    expect(ordered.map((row) => row.id)).toEqual(["known", "unknown"]);

    const allocations = allocateFefo({
      requestedQty: 5,
      timezone,
      now,
      batches: [
        batch({
          id: "unknown",
          quantityRemaining: 20,
          unitCostMinor: 50,
          expiryDateKnown: false,
          expiryDate: null,
        }),
        batch({
          id: "known",
          quantityRemaining: 2,
          unitCostMinor: 80,
          expiryDateKnown: true,
          expiryDate: "2026-08-15",
        }),
      ],
    });

    expect(allocations.map((row) => row.batchId)).toEqual([
      "known",
      "unknown",
    ]);
    expect(allocations[0]?.quantity).toBe(2);
    expect(allocations[1]?.quantity).toBe(3);
    expect(allocations[1]?.expiryDate).toBeNull();
  });

  it("throws when saleable stock is insufficient", () => {
    expect(() =>
      allocateFefo({
        requestedQty: 5,
        timezone,
        now,
        batches: [
          batch({
            id: "small",
            quantityRemaining: 2,
            expiryDateKnown: true,
            expiryDate: "2026-08-01",
          }),
          batch({
            id: "expired-status",
            quantityRemaining: 50,
            status: "expired",
            expiryDateKnown: true,
            expiryDate: "2026-01-01",
          }),
          batch({
            id: "past-date",
            quantityRemaining: 50,
            status: "active",
            expiryDateKnown: true,
            expiryDate: "2026-07-01",
          }),
          batch({
            id: "depleted",
            quantityRemaining: 0,
            status: "depleted",
          }),
          batch({
            id: "voided",
            quantityRemaining: 10,
            status: "voided",
          }),
        ],
      }),
    ).toThrow(InsufficientStockError);
  });
});
