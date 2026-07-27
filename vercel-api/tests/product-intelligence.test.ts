import {describe, expect, it} from "vitest";
import {
  calculatePotentialProfit,
  daysRemainingForBusiness,
  expiryStatusForDate,
} from "../src/services/inventory/product-intelligence";

describe("product intelligence", () => {
  it("calculates the Shoe potential-profit example in minor units", () => {
    expect(
      calculatePotentialProfit({
        quantity: 50,
        unitCostMinor: 2000,
        sellingPriceMinor: 2500,
      }),
    ).toEqual({
      unitPotentialProfitMinor: 500,
      stockCostValueMinor: 100000,
      expectedStockRevenueMinor: 125000,
      potentialProfitRemainingMinor: 25000,
    });
  });

  it("reports a potential loss without changing its sign", () => {
    const result = calculatePotentialProfit({
      quantity: 2,
      unitCostMinor: 3000,
      sellingPriceMinor: 2500,
    });
    expect(result.potentialProfitRemainingMinor).toBe(-1000);
  });

  it("uses the business calendar date for expiry", () => {
    const now = new Date("2026-07-23T00:30:00.000Z");
    expect(
      daysRemainingForBusiness({
        expiryDate: "2026-07-23",
        now,
        timezone: "America/New_York",
      }),
    ).toBe(1);
    expect(
      expiryStatusForDate({
        expiryDate: "2026-07-23",
        now,
        timezone: "UTC",
      }),
    ).toBe("expires_today");
  });
});
