import {describe, expect, it} from "vitest";
import {
  calculatePurchaseTotals,
  lineDiscountMinor,
  lineSubtotalMinor,
  summarizeInventoryBatches,
} from "../src/services/inventory/purchase-intelligence";

describe("purchase calculations", () => {
  it("ports line, discount, tax, delivery, and payment math in minor units", () => {
    const items = [
      {
        quantity: 2,
        unitCostMinor: 1000,
        discountType: "percentage" as const,
        discountValue: 10,
      },
    ];

    expect(lineSubtotalMinor(items[0])).toBe(2000);
    expect(lineDiscountMinor(items[0])).toBe(200);
    expect(
      calculatePurchaseTotals({
        items,
        orderDiscountType: "fixed",
        orderDiscountValue: 1,
        taxPercentage: 5,
        deliveryMinor: 250,
        amountPaidMinor: 1000,
      }),
    ).toEqual({
      subtotalMinor: 2000,
      itemDiscountMinor: 200,
      orderDiscountMinor: 100,
      taxMinor: 85,
      deliveryMinor: 250,
      totalMinor: 2035,
      amountPaidMinor: 1000,
      balanceDueMinor: 1035,
    });
  });

  it("caps fixed discounts and overpayment exactly like PurchaseCalculator", () => {
    expect(
      calculatePurchaseTotals({
        items: [
          {
            quantity: 1.5,
            unitCostMinor: 101,
            discountType: "fixed",
            discountValue: 50,
          },
        ],
        amountPaidMinor: 9999,
      }),
    ).toEqual({
      subtotalMinor: 152,
      itemDiscountMinor: 152,
      orderDiscountMinor: 0,
      taxMinor: 0,
      deliveryMinor: 0,
      totalMinor: 0,
      amountPaidMinor: 0,
      balanceDueMinor: 0,
    });
  });

  it("rejects invalid quantities and percentage discounts", () => {
    expect(() =>
      calculatePurchaseTotals({
        items: [{quantity: 0, unitCostMinor: 100}],
      }),
    ).toThrow("quantity");
    expect(() =>
      calculatePurchaseTotals({
        items: [
          {
            quantity: 1,
            unitCostMinor: 100,
            discountType: "percentage",
            discountValue: 101,
          },
        ],
      }),
    ).toThrow("Percentage discount");
  });
});

describe("purchase batch summaries", () => {
  it("summarizes all remaining batches and preserves batch costs", () => {
    const summary = summarizeInventoryBatches({
      tracksExpiry: true,
      sellingPriceMinor: 300,
      timezone: "UTC",
      reminderThresholdDays: 30,
      now: new Date("2026-07-22T12:00:00.000Z"),
      batches: [
        {
          id: "expired",
          quantityRemaining: 2,
          unitCostMinor: 100,
          expiryDate: "2026-07-21",
          expiryDateKnown: true,
          status: "expired",
        },
        {
          id: "next",
          quantityRemaining: 3,
          unitCostMinor: 150,
          expiryDate: "2026-07-30",
          expiryDateKnown: true,
          status: "active",
        },
        {
          id: "unknown",
          quantityRemaining: 4,
          unitCostMinor: 125,
          expiryDateKnown: false,
          status: "active",
        },
        {
          id: "depleted",
          quantityRemaining: 10,
          unitCostMinor: 999,
          expiryDateKnown: false,
          status: "depleted",
        },
      ],
    });

    expect(summary).toEqual({
      expiryStatus: "mixed",
      nextExpiryDate: "2026-07-21",
      nextExpiryBatchId: "expired",
      nextExpiryBatchQuantity: 2,
      expiringQuantity: 3,
      expiredQuantity: 2,
      unknownExpiryQuantity: 4,
      stockCostValueMinor: 1150,
      expectedStockRevenueMinor: 2700,
      potentialProfitRemainingMinor: 1550,
    });
  });

  it("returns not-tracked expiry fields without losing batch valuation", () => {
    expect(
      summarizeInventoryBatches({
        tracksExpiry: false,
        sellingPriceMinor: 200,
        timezone: "UTC",
        batches: [
          {
            id: "batch",
            quantityRemaining: 2,
            unitCostMinor: 125,
            expiryDateKnown: false,
            status: "active",
          },
        ],
      }),
    ).toMatchObject({
      expiryStatus: "not_tracked",
      stockCostValueMinor: 250,
      expectedStockRevenueMinor: 400,
      potentialProfitRemainingMinor: 150,
    });
  });
});
