import {describe, expect, it} from "vitest";
import {voidSaleSchema} from "../src/http/inventory/sales/void";
import {
  normalizeWritableBranchId,
} from "../src/services/inventory/branch-inventory";

describe("branch-owned mutation validation", () => {
  it("rejects a sale void without branchId", () => {
    const result = voidSaleSchema.safeParse({
      businessId: "business-1",
      saleId: "sale-1",
      reason: "Customer cancelled",
    });

    expect(result.success).toBe(false);
  });

  it("accepts a real East Branch id", () => {
    const result = voidSaleSchema.safeParse({
      businessId: "business-1",
      branchId: "east",
      saleId: "sale-1",
      reason: "Customer cancelled",
    });

    expect(result.success).toBe(true);
    expect(result.data?.branchId).toBe("east");
  });

  it("blocks All Branches as a write target", () => {
    expect(() => normalizeWritableBranchId("all")).toThrow();
    expect(() => normalizeWritableBranchId("all_branches")).toThrow();
  });
});
