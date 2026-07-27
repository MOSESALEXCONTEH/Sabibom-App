import type {Message} from "firebase-admin/messaging";
import {FieldValue} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {adminFirestore} from "../../config/firebase-admin";

type PushPayload = {
  title: string;
  body: string;
  data?: Record<string, string>;
  channelId?: "sabibom_important" | "sabibom_summaries" | "sabibom_general";
};

function sanitizeData(data?: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  if (!data) return out;
  for (const [k, v] of Object.entries(data)) {
    // Keep lock-screen payloads minimal and non-sensitive.
    if (/token|secret|key|password|note/i.test(k)) continue;
    if (typeof v !== "string") continue;
    if (v.length > 200) continue;
    out[k] = v;
  }
  return out;
}

export async function sendPushToUser(uid: string, payload: PushPayload) {
  if (!uid) return {sent: 0};
  const db = adminFirestore();
  const devices = await db
    .collection("users")
    .doc(uid)
    .collection("devices")
    .where("isActive", "==", true)
    .limit(20)
    .get();

  const tokens = devices.docs
    .map((d) => d.data().fcmToken as string | undefined)
    .filter((t): t is string => !!t && t.length > 10);

  // Legacy fallback
  if (tokens.length === 0) {
    const user = await db.collection("users").doc(uid).get();
    const legacy = user.data()?.fcmTokens;
    if (Array.isArray(legacy)) {
      for (const t of legacy) {
        if (typeof t === "string" && t.length > 10) tokens.push(t);
      }
    }
  }

  if (tokens.length === 0) return {sent: 0};

  const messaging = getMessaging();
  const channelId = payload.channelId ?? "sabibom_general";
  let sent = 0;
  for (const token of tokens) {
    const message: Message = {
      token,
      notification: {
        title: payload.title.slice(0, 80),
        body: payload.body.slice(0, 180),
      },
      data: {
        ...sanitizeData(payload.data),
        channel: channelId,
      },
      android: {
        priority: channelId === "sabibom_important" ? "high" : "normal",
        notification: {
          channelId,
        },
      },
    };
    try {
      await messaging.send(message);
      sent += 1;
    } catch (error: unknown) {
      const code = (error as {code?: string})?.code ?? "";
      if (
        code.includes("registration-token-not-registered") ||
        code.includes("invalid-registration-token")
      ) {
        // Deactivate invalid token devices.
        for (const doc of devices.docs) {
          if (doc.data().fcmToken === token) {
            await doc.ref.set(
              {isActive: false, updatedAt: FieldValue.serverTimestamp()},
              {merge: true},
            );
          }
        }
      }
    }
  }
  return {sent};
}

export async function createNotificationForUser(input: {
  userId: string;
  type: string;
  title: string;
  message: string;
  businessId?: string;
  businessName?: string;
  entityType?: string;
  entityId?: string;
  routeName?: string;
  routeParameters?: Record<string, string>;
  deduplicationKey?: string;
  priority?: string;
  category?: string;
  sendPush?: boolean;
  channelId?: PushPayload["channelId"];
}) {
  const db = adminFirestore();
  if (input.deduplicationKey) {
    const eventRef = db.collection("notification_events").doc(input.deduplicationKey);
    const existing = await eventRef.get();
    const state = existing.data()?.state as string | undefined;
    if (state === "active" || state === "delivered") {
      return {id: existing.data()?.notificationId as string | undefined, deduped: true};
    }
  }

  const ref = db.collection("users").doc(input.userId).collection("notifications").doc();
  await ref.set({
    id: ref.id,
    userId: input.userId,
    businessId: input.businessId ?? null,
    businessName: input.businessName ?? null,
    type: input.type,
    category: input.category ?? "system",
    title: input.title,
    message: input.message,
    body: input.message,
    priority: input.priority ?? "normal",
    status: "unread",
    read: false,
    entityType: input.entityType ?? null,
    entityId: input.entityId ?? null,
    routeName: input.routeName ?? null,
    routeParameters: input.routeParameters ?? {},
    deduplicationKey: input.deduplicationKey ?? null,
    generatedBy: "vercel",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  if (input.deduplicationKey) {
    await db.collection("notification_events").doc(input.deduplicationKey).set({
      key: input.deduplicationKey,
      type: input.type,
      businessId: input.businessId ?? null,
      userId: input.userId,
      sourceId: input.entityId ?? null,
      state: "delivered",
      notificationId: ref.id,
      firstGeneratedAt: FieldValue.serverTimestamp(),
      lastGeneratedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  if (input.sendPush) {
    await sendPushToUser(input.userId, {
      title: input.title,
      body: input.message,
      data: {
        notificationId: ref.id,
        routeName: input.routeName ?? "",
        ...(input.routeParameters ?? {}),
      },
      channelId: input.channelId,
    });
  }

  return {id: ref.id, deduped: false};
}
