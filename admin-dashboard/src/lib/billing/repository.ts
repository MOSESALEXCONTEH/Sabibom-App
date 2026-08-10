import { FieldValue } from "firebase-admin/firestore";
import { adminFirestore } from "@/lib/firebase/admin";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS } from "@/lib/platform/collections";
import { writeAdminActivity } from "@/lib/platform-admin/repository";
import {
  decodeCursor,
  encodeCursor,
  type CursorPage,
} from "@/lib/api/pagination";
import type {
  SubscriptionPlanCreate,
  SubscriptionPlanPatch,
} from "@/lib/billing/schemas";

export type SubscriptionPlan = {
  id: string;
  name: string;
  code: string;
  description: string | null;
  priceAmount: number;
  currency: string;
  interval: string;
  features: string[];
  status: "draft" | "active" | "retired" | string;
  createdAt: Date | null;
  updatedAt: Date | null;
};

export type BusinessSubscription = {
  id: string;
  businessId: string;
  planId: string;
  planCode: string | null;
  status: string;
  currentPeriodEnd: Date | null;
  createdAt: Date | null;
  updatedAt: Date | null;
};

export type BillingEvent = {
  id: string;
  type: string;
  businessId: string | null;
  subscriptionId: string | null;
  planId: string | null;
  amount: number | null;
  currency: string | null;
  note: string | null;
  createdAt: Date | null;
};

function mapPlan(
  id: string,
  data: FirebaseFirestore.DocumentData,
): SubscriptionPlan {
  return {
    id,
    name: typeof data.name === "string" ? data.name : id,
    code: typeof data.code === "string" ? data.code : id,
    description:
      typeof data.description === "string" ? data.description : null,
    priceAmount:
      typeof data.priceAmount === "number" ? data.priceAmount : 0,
    currency: typeof data.currency === "string" ? data.currency : "SLE",
    interval: typeof data.interval === "string" ? data.interval : "monthly",
    features: Array.isArray(data.features)
      ? data.features.filter((x): x is string => typeof x === "string")
      : [],
    status: typeof data.status === "string" ? data.status : "draft",
    createdAt: asDate(data.createdAt),
    updatedAt: asDate(data.updatedAt),
  };
}

export async function listSubscriptionPlans(options: {
  limit?: number;
  cursor?: string;
}): Promise<CursorPage<SubscriptionPlan>> {
  const limit = Math.min(options.limit ?? 25, 100);
  let query = adminFirestore()
    .collection(COLLECTIONS.subscriptionPlans)
    .orderBy("createdAt", "desc")
    .limit(limit + 1);

  const cursorId = decodeCursor(options.cursor);
  if (cursorId) {
    const cursorDoc = await adminFirestore()
      .collection(COLLECTIONS.subscriptionPlans)
      .doc(cursorId)
      .get();
    if (cursorDoc.exists) query = query.startAfter(cursorDoc);
  }

  const snap = await query.get().catch(async () =>
    adminFirestore()
      .collection(COLLECTIONS.subscriptionPlans)
      .limit(limit + 1)
      .get(),
  );

  const docs = snap.docs.slice(0, limit);
  const hasMore = snap.docs.length > limit;
  const items = docs.map((doc) => mapPlan(doc.id, doc.data() ?? {}));
  return {
    items,
    nextCursor:
      hasMore && items.length > 0
        ? encodeCursor(items[items.length - 1]!.id)
        : null,
    hasMore,
  };
}

export async function createSubscriptionPlan(input: {
  plan: SubscriptionPlanCreate;
  actorUid: string;
  actorName: string | null;
  actorRole: string;
  requestId?: string | null;
}): Promise<SubscriptionPlan> {
  const ref = adminFirestore().collection(COLLECTIONS.subscriptionPlans).doc();
  const payload = {
    id: ref.id,
    name: input.plan.name,
    code: input.plan.code.toLowerCase(),
    description: input.plan.description ?? null,
    priceAmount: input.plan.priceAmount,
    currency: input.plan.currency.toUpperCase(),
    interval: input.plan.interval,
    features: input.plan.features,
    status: "draft" as const,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    createdBy: input.actorUid,
  };
  await ref.set(payload);
  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType: "create_subscription_plan",
    targetType: "subscription_plan",
    targetId: ref.id,
    targetLabel: input.plan.code,
    description: `Created draft plan ${input.plan.code}`,
    requestId: input.requestId ?? null,
  });
  return {
    id: ref.id,
    name: input.plan.name,
    code: input.plan.code.toLowerCase(),
    description: input.plan.description ?? null,
    priceAmount: input.plan.priceAmount,
    currency: input.plan.currency.toUpperCase(),
    interval: input.plan.interval,
    features: input.plan.features,
    status: "draft",
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

export async function patchSubscriptionPlan(input: {
  id: string;
  patch: SubscriptionPlanPatch;
  actorUid: string;
  actorName: string | null;
  actorRole: string;
  requestId?: string | null;
}): Promise<SubscriptionPlan | null> {
  const ref = adminFirestore()
    .collection(COLLECTIONS.subscriptionPlans)
    .doc(input.id);
  const snap = await ref.get();
  if (!snap.exists) return null;
  const previous = mapPlan(snap.id, snap.data() ?? {});

  await ref.set(
    {
      ...input.patch,
      ...(input.patch.currency
        ? { currency: input.patch.currency.toUpperCase() }
        : {}),
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: input.actorUid,
    },
    { merge: true },
  );

  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType: "patch_subscription_plan",
    targetType: "subscription_plan",
    targetId: input.id,
    targetLabel: previous.code,
    description: `Updated plan ${previous.code}`,
    previousStateSnapshot: { status: previous.status },
    newStateSnapshot: input.patch as Record<string, unknown>,
    requestId: input.requestId ?? null,
  });

  const updated = await ref.get();
  return mapPlan(updated.id, updated.data() ?? {});
}

export async function listBusinessSubscriptions(options: {
  limit?: number;
  cursor?: string;
}): Promise<CursorPage<BusinessSubscription>> {
  const limit = Math.min(options.limit ?? 25, 100);
  let query = adminFirestore()
    .collection(COLLECTIONS.businessSubscriptions)
    .orderBy("createdAt", "desc")
    .limit(limit + 1);

  const cursorId = decodeCursor(options.cursor);
  if (cursorId) {
    const cursorDoc = await adminFirestore()
      .collection(COLLECTIONS.businessSubscriptions)
      .doc(cursorId)
      .get();
    if (cursorDoc.exists) query = query.startAfter(cursorDoc);
  }

  const snap = await query.get().catch(async () =>
    adminFirestore()
      .collection(COLLECTIONS.businessSubscriptions)
      .limit(limit + 1)
      .get(),
  );

  const docs = snap.docs.slice(0, limit);
  const hasMore = snap.docs.length > limit;
  const items: BusinessSubscription[] = docs.map((doc) => {
    const data = doc.data() ?? {};
    return {
      id: doc.id,
      businessId:
        typeof data.businessId === "string" ? data.businessId : "",
      planId: typeof data.planId === "string" ? data.planId : "",
      planCode: typeof data.planCode === "string" ? data.planCode : null,
      status: typeof data.status === "string" ? data.status : "unknown",
      currentPeriodEnd: asDate(data.currentPeriodEnd),
      createdAt: asDate(data.createdAt),
      updatedAt: asDate(data.updatedAt),
    };
  });

  return {
    items,
    nextCursor:
      hasMore && items.length > 0
        ? encodeCursor(items[items.length - 1]!.id)
        : null,
    hasMore,
  };
}

export async function listBillingEvents(options: {
  limit?: number;
  cursor?: string;
}): Promise<CursorPage<BillingEvent>> {
  const limit = Math.min(options.limit ?? 25, 100);
  let query = adminFirestore()
    .collection(COLLECTIONS.billingEvents)
    .orderBy("createdAt", "desc")
    .limit(limit + 1);

  const cursorId = decodeCursor(options.cursor);
  if (cursorId) {
    const cursorDoc = await adminFirestore()
      .collection(COLLECTIONS.billingEvents)
      .doc(cursorId)
      .get();
    if (cursorDoc.exists) query = query.startAfter(cursorDoc);
  }

  const snap = await query.get().catch(async () =>
    adminFirestore()
      .collection(COLLECTIONS.billingEvents)
      .limit(limit + 1)
      .get(),
  );

  const docs = snap.docs.slice(0, limit);
  const hasMore = snap.docs.length > limit;
  const items: BillingEvent[] = docs.map((doc) => {
    const data = doc.data() ?? {};
    return {
      id: doc.id,
      type: typeof data.type === "string" ? data.type : "unknown",
      businessId:
        typeof data.businessId === "string" ? data.businessId : null,
      subscriptionId:
        typeof data.subscriptionId === "string"
          ? data.subscriptionId
          : null,
      planId: typeof data.planId === "string" ? data.planId : null,
      amount: typeof data.amount === "number" ? data.amount : null,
      currency: typeof data.currency === "string" ? data.currency : null,
      note: typeof data.note === "string" ? data.note : null,
      createdAt: asDate(data.createdAt),
    };
  });

  return {
    items,
    nextCursor:
      hasMore && items.length > 0
        ? encodeCursor(items[items.length - 1]!.id)
        : null,
    hasMore,
  };
}
