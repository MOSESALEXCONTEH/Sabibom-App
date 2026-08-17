import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {errors} from "../../utils/api-errors";
import {getEnv} from "../../config/env";

export const ENTITLEMENT_KEYS = {
  branchesMax: "branches.max",
  staffMax: "staff.max",
  reportsHistoryDays: "reports.history_days",
  reportsAdvanced: "reports.advanced",
  reportsExport: "reports.export",
  sabiDailyRequests: "sabi.daily_requests",
  messagingBulk: "messaging.bulk",
  approvalsEnabled: "approvals.enabled",
  backupEnabled: "backup.enabled",
  adsEnabled: "ads.enabled",
} as const;

export type BillingTier = "free" | "pro" | "complimentary";
export type EntitlementValues = Record<string, boolean | number>;

export const FREE_ENTITLEMENTS: EntitlementValues = {
  [ENTITLEMENT_KEYS.branchesMax]: 1,
  [ENTITLEMENT_KEYS.staffMax]: 2,
  [ENTITLEMENT_KEYS.reportsHistoryDays]: 30,
  [ENTITLEMENT_KEYS.reportsAdvanced]: false,
  [ENTITLEMENT_KEYS.reportsExport]: false,
  [ENTITLEMENT_KEYS.sabiDailyRequests]: 10,
  [ENTITLEMENT_KEYS.messagingBulk]: false,
  [ENTITLEMENT_KEYS.approvalsEnabled]: false,
  [ENTITLEMENT_KEYS.backupEnabled]: false,
  [ENTITLEMENT_KEYS.adsEnabled]: true,
};

export const PRO_ENTITLEMENTS: EntitlementValues = {
  [ENTITLEMENT_KEYS.branchesMax]: -1,
  [ENTITLEMENT_KEYS.staffMax]: -1,
  [ENTITLEMENT_KEYS.reportsHistoryDays]: -1,
  [ENTITLEMENT_KEYS.reportsAdvanced]: true,
  [ENTITLEMENT_KEYS.reportsExport]: true,
  [ENTITLEMENT_KEYS.sabiDailyRequests]: -1,
  [ENTITLEMENT_KEYS.messagingBulk]: true,
  [ENTITLEMENT_KEYS.approvalsEnabled]: true,
  [ENTITLEMENT_KEYS.backupEnabled]: true,
  [ENTITLEMENT_KEYS.adsEnabled]: false,
};

function asDate(value: unknown): Date | null {
  if (value instanceof Date) return value;
  if (value && typeof value === "object" && "toDate" in value) {
    const candidate = (value as {toDate?: unknown}).toDate;
    if (typeof candidate === "function") {
      return candidate.call(value) as Date;
    }
  }
  return null;
}

export function subscriptionHasAccess(
  data: Record<string, unknown>,
  now = new Date(),
): boolean {
  const status = typeof data.status === "string" ? data.status : "";
  if (!["active", "trialing", "grace_period", "canceled", "cancelled"].includes(status)) {
    return false;
  }
  const end = asDate(
    status === "trialing"
      ? data.trialEndsAt ?? data.currentPeriodEnd
      : data.currentPeriodEnd,
  );
  if ((status === "canceled" || status === "cancelled") && !end) return false;
  return !end || end.getTime() > now.getTime();
}

function normalizedOverrides(value: unknown): EntitlementValues {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const result: EntitlementValues = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (!Object.values(ENTITLEMENT_KEYS).includes(key as never)) continue;
    if (typeof item === "boolean" || (typeof item === "number" && Number.isFinite(item))) {
      result[key] = item;
    }
  }
  return result;
}

export function entitlementsForTier(
  tier: BillingTier,
  overrides?: unknown,
): EntitlementValues {
  const defaults = tier === "free" ? FREE_ENTITLEMENTS : PRO_ENTITLEMENTS;
  return {...defaults, ...normalizedOverrides(overrides)};
}

export async function resolveBusinessEntitlements(input: {
  db: Firestore;
  businessId: string;
  now?: Date;
}): Promise<{tier: BillingTier; values: EntitlementValues; source: string}> {
  const subscription = await input.db
    .collection("business_subscriptions")
    .doc(input.businessId)
    .get();
  if (!subscription.exists) {
    return {tier: "free", values: {...FREE_ENTITLEMENTS}, source: "free_default"};
  }
  const subscriptionData = subscription.data() ?? {};
  if (!subscriptionHasAccess(subscriptionData, input.now)) {
    return {tier: "free", values: {...FREE_ENTITLEMENTS}, source: "downgraded"};
  }

  const planId = typeof subscriptionData.planId === "string" ? subscriptionData.planId : "";
  const plan = planId
    ? await input.db.collection("subscription_plans").doc(planId).get()
    : null;
  const planData = plan?.data() ?? {};
  const accessType = subscriptionData.accessType;
  const declaredTier = typeof planData.tier === "string" ? planData.tier.toLowerCase() : "";
  const searchable = `${planId} ${typeof planData.name === "string" ? planData.name : ""}`.toLowerCase();
  const tier: BillingTier = accessType === "complimentary"
    ? "complimentary"
    : declaredTier === "free" || searchable.includes("free") || planData.price === 0
      ? "free"
      : "pro";
  return {
    tier,
    values: entitlementsForTier(tier, planData.limits),
    source: accessType === "complimentary" ? "complimentary" : "active_plan",
  };
}

export async function consumeSabiRequest(input: {
  db: Firestore;
  businessId: string;
  uid: string;
  now?: Date;
}): Promise<void> {
  const now = input.now ?? new Date();
  const resolved = await resolveBusinessEntitlements({
    db: input.db,
    businessId: input.businessId,
    now,
  });
  const limit = Number(resolved.values[ENTITLEMENT_KEYS.sabiDailyRequests] ?? 0);
  if (limit === -1) return;

  const day = now.toISOString().slice(0, 10);
  const usageRef = input.db.collection("billing_usage").doc(`${input.businessId}_${day}`);
  await input.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(usageRef);
    const count = typeof snapshot.data()?.sabiRequests === "number"
      ? Number(snapshot.data()?.sabiRequests)
      : 0;
    const limitReached = count >= limit;
    if (limitReached && getEnv().billingEnforcementMode === "enforced") {
      throw errors.planLimitReached(
        `The Free plan includes ${limit} Sabi requests per day. Upgrade to Pro for unlimited Sabi access.`,
      );
    }
    if (limitReached) {
      console.warn("[sabibom-api] billing shadow limit reached", {
        businessId: input.businessId,
        entitlement: ENTITLEMENT_KEYS.sabiDailyRequests,
        limit,
      });
    }
    transaction.set(usageRef, {
      businessId: input.businessId,
      date: day,
      sabiRequests: count + 1,
      lastUserId: input.uid,
      updatedAt: FieldValue.serverTimestamp(),
      limitReached,
      createdAt: snapshot.exists
        ? snapshot.data()?.createdAt ?? FieldValue.serverTimestamp()
        : FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

export async function materializeBusinessEntitlements(input: {
  db: Firestore;
  businessId: string;
  now?: Date;
}): Promise<{tier: BillingTier; values: EntitlementValues; source: string}> {
  const resolved = await resolveBusinessEntitlements(input);
  await input.db.collection("business_entitlements").doc(input.businessId).set({
    businessId: input.businessId,
    tier: resolved.tier,
    values: resolved.values,
    source: resolved.source,
    schemaVersion: 1,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return resolved;
}

export async function enforceBusinessCapacity(input: {
  db: Firestore;
  businessId: string;
  entitlement: typeof ENTITLEMENT_KEYS.branchesMax | typeof ENTITLEMENT_KEYS.staffMax;
  currentUsage: number;
  featureName: string;
}): Promise<void> {
  const resolved = await resolveBusinessEntitlements({
    db: input.db,
    businessId: input.businessId,
  });
  const limit = Number(resolved.values[input.entitlement] ?? 0);
  if (hasEntitlementCapacity(limit, input.currentUsage)) return;

  if (getEnv().billingEnforcementMode === "enforced") {
    throw errors.planLimitReached(
      `Your current plan allows ${limit} ${input.featureName}. Upgrade to add more.`,
    );
  }
  console.warn("[sabibom-api] billing shadow capacity reached", {
    businessId: input.businessId,
    entitlement: input.entitlement,
    currentUsage: input.currentUsage,
    limit,
  });
}

export function hasEntitlementCapacity(limit: number, currentUsage: number): boolean {
  return limit === -1 || currentUsage < limit;
}
