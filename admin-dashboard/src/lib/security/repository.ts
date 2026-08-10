import { adminFirestore } from "@/lib/firebase/admin";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS } from "@/lib/platform/collections";
import {
  decodeCursor,
  encodeCursor,
  type CursorPage,
} from "@/lib/api/pagination";
import { maskUid } from "@/lib/utils/mask";
import {
  maskIp,
  maskSecurityMetadata,
} from "@/lib/security/masking";

export type SecurityEventCategory =
  | "auth"
  | "app_check"
  | "rate_limit"
  | "security"
  | "other";

export type SecurityEvent = {
  id: string;
  category: SecurityEventCategory | string;
  eventType: string;
  severity: string;
  actorUid: string | null;
  ipHash: string | null;
  userAgent: string | null;
  message: string | null;
  metadata: Record<string, unknown> | null;
  createdAt: Date | null;
};

export type PublicSecurityEvent = SecurityEvent;

function normalizeCategory(value: unknown): string {
  if (typeof value !== "string") return "security";
  const v = value.toLowerCase();
  if (v === "auth" || v === "authentication") return "auth";
  if (v === "app_check" || v === "appcheck") return "app_check";
  if (v === "rate_limit" || v === "ratelimit") return "rate_limit";
  if (v === "security") return "security";
  return v;
}

function mapEvent(
  id: string,
  data: FirebaseFirestore.DocumentData,
): SecurityEvent {
  const rawIp =
    typeof data.ipHash === "string"
      ? data.ipHash
      : typeof data.ip === "string"
        ? data.ip
        : typeof data.clientIp === "string"
          ? data.clientIp
          : null;

  const metadataRaw =
    data.metadata && typeof data.metadata === "object"
      ? (data.metadata as Record<string, unknown>)
      : null;

  return {
    id,
    category: normalizeCategory(data.category ?? data.kind ?? data.type),
    eventType:
      typeof data.eventType === "string"
        ? data.eventType
        : typeof data.type === "string"
          ? data.type
          : "unknown",
    severity:
      typeof data.severity === "string" ? data.severity : "info",
    actorUid:
      typeof data.actorUid === "string"
        ? data.actorUid
        : typeof data.uid === "string"
          ? data.uid
          : null,
    ipHash: maskIp(rawIp),
    userAgent:
      typeof data.userAgent === "string" ? data.userAgent : null,
    message:
      typeof data.message === "string"
        ? data.message
        : typeof data.description === "string"
          ? data.description
          : null,
    metadata: maskSecurityMetadata(metadataRaw),
    createdAt: asDate(data.createdAt ?? data.timestamp),
  };
}

export function toPublicSecurityEvent(event: SecurityEvent): PublicSecurityEvent {
  return {
    ...event,
    actorUid: maskUid(event.actorUid),
    ipHash: event.ipHash ? maskIp(event.ipHash) ?? event.ipHash : null,
    metadata: maskSecurityMetadata(event.metadata),
  };
}

export async function listSecurityEvents(options: {
  limit?: number;
  cursor?: string;
  category?: string;
}): Promise<CursorPage<SecurityEvent>> {
  const limit = Math.min(options.limit ?? 25, 100);
  let query: FirebaseFirestore.Query = adminFirestore()
    .collection(COLLECTIONS.platformSecurityEvents)
    .orderBy("createdAt", "desc")
    .limit(limit + 1);

  if (options.category) {
    query = adminFirestore()
      .collection(COLLECTIONS.platformSecurityEvents)
      .where("category", "==", options.category)
      .orderBy("createdAt", "desc")
      .limit(limit + 1);
  }

  const cursorId = decodeCursor(options.cursor);
  if (cursorId) {
    const cursorDoc = await adminFirestore()
      .collection(COLLECTIONS.platformSecurityEvents)
      .doc(cursorId)
      .get();
    if (cursorDoc.exists) query = query.startAfter(cursorDoc);
  }

  const snap = await query.get().catch(async () => {
    let fallback: FirebaseFirestore.Query = adminFirestore()
      .collection(COLLECTIONS.platformSecurityEvents)
      .limit(limit + 1);
    if (options.category) {
      fallback = adminFirestore()
        .collection(COLLECTIONS.platformSecurityEvents)
        .where("category", "==", options.category)
        .limit(limit + 1);
    }
    return fallback.get();
  });

  const docs = snap.docs.slice(0, limit);
  const hasMore = snap.docs.length > limit;
  const items = docs.map((doc) => mapEvent(doc.id, doc.data() ?? {}));

  return {
    items,
    nextCursor:
      hasMore && items.length > 0
        ? encodeCursor(items[items.length - 1]!.id)
        : null,
    hasMore,
  };
}
