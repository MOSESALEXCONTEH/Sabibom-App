import {describe, expect, it} from "vitest";
import {createProductSchema} from "../src/http/inventory/products/create";

const validProduct = {
  businessId: "business-1",
  branchId: "east",
  productId: "550e8400-e29b-41d4-a716-446655440000",
  name: "Rice",
  sellingPriceMinor: 2000,
  costPriceMinor: 1000,
  trackStock: true,
  quantity: 10,
  lowStockThreshold: 2,
  unit: "Piece",
  tracksExpiry: true,
  initialStockExpiryDateKnown: true,
};

describe("product create validation", () => {
  it("accepts the app UTC expiry payload", () => {
    const result = createProductSchema.safeParse({
      ...validProduct,
      initialStockExpiryDate: "2026-08-20T12:00:00.000Z",
    });
    expect(result.success).toBe(true);
  });

  it("accepts legacy local ISO expiry payloads", () => {
    const result = createProductSchema.safeParse({
      ...validProduct,
      initialStockExpiryDate: "2026-08-20T00:00:00.000",
    });
    expect(result.success).toBe(true);
  });

  it("rejects an invalid expiry payload", () => {
    const result = createProductSchema.safeParse({
      ...validProduct,
      initialStockExpiryDate: "not-a-date",
    });
    expect(result.success).toBe(false);
  });
});
