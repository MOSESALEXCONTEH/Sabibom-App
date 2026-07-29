import {describe, expect, it} from "vitest";
import {voidSaleSchema} from "../src/http/inventory/sales/void";
import {completeSaleSchema} from "../src/http/inventory/sales/complete";
import {
  completePurchaseSchema,
} from "../src/http/inventory/purchases/complete";
import {
  normalizeWritableBranchId,
  requireBranchIdInBody,
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

  it("rejects sale completion without branchId", () => {
    const result = completeSaleSchema.safeParse({
      businessId: "business-1",
      saleId: "sale-1",
      items: [{
        saleItemId: "line-1",
        name: "Rice",
        quantity: 1,
        unitPriceMinor: 1000,
        trackStock: false,
      }],
      paymentMethod: "cash",
      amountPaidMinor: 1000,
      currencyCode: "SLE",
      currencySymbol: "Le",
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

  it("accepts East branch identity on sale completion", () => {
    const result = completeSaleSchema.safeParse({
      businessId: "business-1",
      branchId: "east",
      branchNameSnapshot: "East Branch",
      branchCodeSnapshot: "EAST",
      saleId: "00000000-0000-4000-8000-000000000001",
      items: [{
        saleItemId: "line-1",
        name: "Rice",
        quantity: 1,
        unitPriceMinor: 1000,
        trackStock: false,
      }],
      paymentMethod: "cash",
      amountPaidMinor: 1000,
    });

    expect(result.success).toBe(true);
    expect(result.data?.branchId).toBe("east");
  });

  it("rejects purchase completion without branchId", () => {
    const result = completePurchaseSchema.safeParse({
      businessId: "business-1",
      purchaseId: "00000000-0000-4000-8000-000000000002",
      supplierId: "supplier-1",
      supplierName: "Supplier",
      items: [{
        purchaseItemId: "line-1",
        productId: "product-1",
        name: "Rice",
        quantity: 1,
        unitCostMinor: 1000,
        trackStock: true,
      }],
    });

    expect(result.success).toBe(false);
  });

  it("returns branch_required HTTP 400 semantics for a missing branch", () => {
    try {
      requireBranchIdInBody({businessId: "business-1"});
      throw new Error("Expected branch validation to fail.");
    } catch (error) {
      expect(error).toMatchObject({code: "branch_required", status: 400});
    }
  });

  it("accepts East branch identity on purchase completion", () => {
    const result = completePurchaseSchema.safeParse({
      businessId: "business-1",
      branchId: "east",
      branchNameSnapshot: "East Branch",
      branchCodeSnapshot: "EAST",
      purchaseId: "00000000-0000-4000-8000-000000000002",
      supplierId: "supplier-1",
      supplierName: "Supplier",
      items: [{
        purchaseItemId: "line-1",
        productId: "product-1",
        name: "Rice",
        quantity: 1,
        unitCostMinor: 1000,
        trackStock: true,
      }],
    });

    expect(result.success).toBe(true);
    expect(result.data?.branchId).toBe("east");
  });

  it("blocks All Branches as a write target", () => {
    expect(() => normalizeWritableBranchId("all")).toThrow();
    expect(() => normalizeWritableBranchId("all_branches")).toThrow();
  });
});
