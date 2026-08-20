import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {ledgerId, notificationId} from "./ids";
import {
  channelDecision,
  NotificationCategory,
  resolveNotificationPolicy,
} from "./policy";

export interface NotificationContent {
  eventId: string;
  userId: string;
  category: NotificationCategory;
  type: string;
  title: string;
  body: string;
  businessId: string;
  businessName?: string;
  branchId?: string;
  entityType: string;
  entityId: string;
  routeName?: string;
  routeParameters?: Record<string, string>;
  priority?: "normal" | "high";
}

function safe(value: string | undefined, maximum = 200): string {
  return (value ?? "").trim().slice(0, maximum);
}

export function payloadData(input: NotificationContent, inAppId: string): Record<string, string> {
  const routeParameters = Object.fromEntries(
    Object.entries(input.routeParameters ?? {})
      .filter(([key, value]) => /^[A-Za-z][A-Za-z0-9]{0,39}$/.test(key) && typeof value === "string")
      .map(([key, value]) => [key, safe(value, 120)]),
  );
  return {
    notificationId: inAppId,
    type: safe(input.type, 80),
    title: safe(input.title, 80),
    body: safe(input.body, 180),
    businessId: safe(input.businessId, 120),
    branchId: safe(input.branchId, 120),
    entityType: safe(input.entityType, 80),
    entityId: safe(input.entityId, 120),
    routeName: safe(input.routeName, 100),
    routeParameters: JSON.stringify(input.routeParameters ?? {}).slice(0, 500),
    ...routeParameters,
    channel: input.priority === "high" ? "sabibom_important" : "sabibom_general",
  };
}

async function tokensForUser(userId: string): Promise<string[]> {
  const db = getFirestore();
  const devices = await db.collection("users").doc(userId)
    .collection("devices").limit(100).get();
  const active = devices.docs.filter((doc) => {
    const data = doc.data();
    return data.isActive === true && data.notificationsEnabled !== false;
  }).map((doc) => doc.data().fcmToken)
    .filter((token): token is string => typeof token === "string" && token.length > 10);
  if (active.length > 0) return [...new Set(active)].slice(0, 500);
  const user = await db.collection("users").doc(userId).get();
  const legacy = user.data()?.fcmTokens;
  return [...new Set(Array.isArray(legacy) ? legacy.filter(
    (token): token is string => typeof token === "string" && token.length > 10,
  ) : [])].slice(0, 500);
}

export async function deliverNotification(input: NotificationContent): Promise<void> {
  const db = getFirestore();
  const userRef = db.collection("users").doc(input.userId);
  const [preferenceSnap, userSnap] = await Promise.all([
    userRef.collection("notification_preferences").doc(input.businessId).get(),
    userRef.get(),
  ]);
  const businessPreferences = preferenceSnap.exists ? preferenceSnap.data() : undefined;
  const legacyValue = userSnap.data()?.notificationPrefs;
  const legacyPreferences = legacyValue && typeof legacyValue === "object" ?
    legacyValue as Record<string, unknown> : undefined;
  const policy = resolveNotificationPolicy(
    businessPreferences, legacyPreferences, input.category,
  );
  const channels = channelDecision(policy, new Date());
  const deliveryId = ledgerId(input.eventId, input.userId);
  const inAppId = notificationId(input.eventId, input.userId);
  const ledgerRef = db.collection("notification_delivery_ledger").doc(deliveryId);
  const notificationRef = userRef.collection("notifications").doc(inAppId);

  const reserved = await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ledgerRef);
    if (existing.exists) return false;
    if (channels.inApp) {
      transaction.create(notificationRef, {
        id: inAppId,
        userId: input.userId,
        businessId: input.businessId,
        businessName: input.businessName ?? null,
        branchId: input.branchId ?? null,
        type: input.type,
        category: input.category === "approval" ? "approvals" : "staff",
        title: safe(input.title, 120),
        message: safe(input.body, 500),
        body: safe(input.body, 500),
        priority: input.priority ?? "normal",
        status: "unread",
        read: false,
        entityType: input.entityType,
        entityId: input.entityId,
        routeName: input.routeName ?? null,
        routeParameters: input.routeParameters ?? {},
        deduplicationKey: input.eventId,
        sourceType: input.entityType,
        sourceId: input.entityId,
        generatedBy: "cloud_functions",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.create(ledgerRef, {
      id: deliveryId,
      eventId: input.eventId,
      userId: input.userId,
      businessId: input.businessId,
      sourceType: input.entityType,
      sourceId: input.entityId,
      notificationId: channels.inApp ? inAppId : null,
      inAppState: channels.inApp ? "created" : "suppressed",
      pushState: channels.push ? "reserved" :
        (channels.pushQuietSuppressed ? "quiet_hours" : "suppressed"),
      pushAttempted: channels.push,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return channels.push;
  });

  if (!reserved) return;
  let pushState = "no_tokens";
  let successCount = 0;
  let failureCount = 0;
  try {
    const tokens = await tokensForUser(input.userId);
    if (tokens.length > 0) {
      const data = payloadData(input, inAppId);
      const result = await getMessaging().sendEachForMulticast({
        tokens,
        notification: {title: data.title, body: data.body},
        data,
        android: {
          priority: input.priority === "high" ? "high" : "normal",
          notification: {channelId: data.channel},
        },
      });
      successCount = result.successCount;
      failureCount = result.failureCount;
      pushState = successCount > 0 ? "sent" : "failed";
    }
  } catch (error) {
    pushState = "failed";
    console.warn("notification push attempt failed", {
      eventId: input.eventId,
      userId: input.userId,
      error: error instanceof Error ? error.message : "unknown",
    });
  }
  try {
    await ledgerRef.set({
      pushState,
      pushSuccessCount: successCount,
      pushFailureCount: failureCount,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } catch (error) {
    console.warn("notification ledger result update failed", {
      eventId: input.eventId,
      error: error instanceof Error ? error.message : "unknown",
    });
  }
}

export async function deliverMany(inputs: readonly NotificationContent[]): Promise<void> {
  await Promise.all(inputs.map(async (input) => {
    try {
      await deliverNotification(input);
    } catch (error) {
      console.error("notification delivery isolated failure", {
        eventId: input.eventId,
        userId: input.userId,
        error: error instanceof Error ? error.message : "unknown",
      });
    }
  }));
}
