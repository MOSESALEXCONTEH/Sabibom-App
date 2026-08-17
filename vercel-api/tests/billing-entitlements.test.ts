import {describe, expect, it} from "vitest";
import {
  ENTITLEMENT_KEYS,
  entitlementsForTier,
  hasEntitlementCapacity,
  subscriptionHasAccess,
} from "../src/services/billing/entitlements";
import {
  normalizeGooglePlaySubscription,
  purchaseTokenHash,
} from "../src/services/billing/google-play";
import {verifyGooglePlaySchema} from "../src/http/billing/verify-google-play";

describe("billing entitlements", () => {
  it("blocks capacity at the Free limit and leaves Pro unlimited", () => {
    expect(hasEntitlementCapacity(1, 0)).toBe(true);
    expect(hasEntitlementCapacity(1, 1)).toBe(false);
    expect(hasEntitlementCapacity(2, 2)).toBe(false);
    expect(hasEntitlementCapacity(-1, 5000)).toBe(true);
  });
  it("keeps core Free defaults and applies safe plan overrides", () => {
    const values = entitlementsForTier("free", {
      [ENTITLEMENT_KEYS.staffMax]: 4,
      [ENTITLEMENT_KEYS.reportsExport]: true,
      unknown: 999,
    });
    expect(values[ENTITLEMENT_KEYS.branchesMax]).toBe(1);
    expect(values[ENTITLEMENT_KEYS.staffMax]).toBe(4);
    expect(values[ENTITLEMENT_KEYS.reportsExport]).toBe(true);
    expect(values.unknown).toBeUndefined();
  });

  it("downgrades expired and paused subscriptions", () => {
    const now = new Date("2026-08-16T12:00:00.000Z");
    expect(subscriptionHasAccess({status: "paused"}, now)).toBe(false);
    expect(subscriptionHasAccess({
      status: "active",
      currentPeriodEnd: new Date("2026-08-16T11:59:59.000Z"),
    }, now)).toBe(false);
    expect(subscriptionHasAccess({
      status: "canceled",
      currentPeriodEnd: new Date("2026-08-17T12:00:00.000Z"),
    }, now)).toBe(true);
  });
});

describe("Google Play subscription validation", () => {
  it("normalizes an active verified subscription", () => {
    const value = normalizeGooglePlaySubscription({
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
      startTime: "2026-08-01T00:00:00.000Z",
      lineItems: [{
        productId: "sabibom_pro_monthly",
        expiryTime: "2026-09-01T00:00:00.000Z",
        autoRenewingPlan: {autoRenewEnabled: true},
      }],
    }, "sabibom_pro_monthly");
    expect(value.status).toBe("active");
    expect(value.acknowledgementPending).toBe(true);
    expect(value.cancelAtPeriodEnd).toBe(false);
  });

  it("rejects a product mismatch and hashes tokens deterministically", () => {
    expect(() => normalizeGooglePlaySubscription({
      lineItems: [{productId: "different", expiryTime: "2026-09-01T00:00:00.000Z"}],
    }, "sabibom_pro_monthly")).toThrow(/does not match/i);
    expect(purchaseTokenHash("token-value")).toHaveLength(64);
    expect(purchaseTokenHash("token-value")).toBe(purchaseTokenHash("token-value"));
  });

  it("requires a business, product, and non-empty purchase token", () => {
    expect(verifyGooglePlaySchema.safeParse({
      businessId: "business-1",
      productId: "sabibom_pro_monthly",
      purchaseToken: "x".repeat(30),
    }).success).toBe(true);
    expect(verifyGooglePlaySchema.safeParse({
      businessId: "business-1",
      productId: "sabibom_pro_monthly",
      purchaseToken: "",
    }).success).toBe(false);
  });
});
