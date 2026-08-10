import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { adminFirestore } from "@/lib/firebase/admin";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS } from "@/lib/platform/collections";
import { writeAdminActivity } from "@/lib/platform-admin/repository";
import {
  decodeCursor,
  encodeCursor,
  type CursorPage,
} from "@/lib/api/pagination";
import { maskEmail, maskUid } from "@/lib/utils/mask";

export const BETA_TESTER_STATUSES = [
  "invited",
  "active",
  "revoked",
] as const;

export const betaTesterCreateSchema = z.object({
  email: z.string().trim().email().max(254),
  displayName: z.string().trim().max(120).optional().nullable(),
  uid: z.string().trim().min(1).max(128).optional().nullable(),
  platform: z
    .enum(["ios", "android", "web", "all"])
    .default("all"),
  notes: z.string().trim().max(2000).optional().nullable(),
});

export const betaTesterPatchSchema = z.object({
  status: z.enum(BETA_TESTER_STATUSES).optional(),
  displayName: z.string().trim().max(120).optional().nullable(),
  platform: z.enum(["ios", "android", "web", "all"]).optional(),
  notes: z.string().trim().max(2000).optional().nullable(),
  uid: z.string().trim().min(1).max(128).optional().nullable(),
});

export type BetaTester = {
  id: string;
  email: string;
  displayName: string | null;
  uid: string | null;
  platform: string;
  status: (typeof BETA_TESTER_STATUSES)[number] | string;
  notes: string | null;
  invitedBy: string | null;
  createdAt: Date | null;
  updatedAt: Date | null;
};

export type PublicBetaTester = Omit<BetaTester, "email" | "uid"> & {
  email: string | null;
  uid: string | null;
};

function mapTester(
  id: string,
  data: FirebaseFirestore.DocumentData,
): BetaTester {
  const status = typeof data.status === "string" ? data.status : "invited";
  return {
    id,
    email: typeof data.email === "string" ? data.email : "",
    displayName:
      typeof data.displayName === "string" ? data.displayName : null,
    uid: typeof data.uid === "string" ? data.uid : null,
    platform: typeof data.platform === "string" ? data.platform : "all",
    status,
    notes: typeof data.notes === "string" ? data.notes : null,
    invitedBy: typeof data.invitedBy === "string" ? data.invitedBy : null,
    createdAt: asDate(data.createdAt),
    updatedAt: asDate(data.updatedAt),
  };
}

export function toPublicBetaTester(row: BetaTester): PublicBetaTester {
  return {
    ...row,
    email: maskEmail(row.email),
    uid: maskUid(row.uid),
  };
}

export async function listBetaTesters(options: {
  limit?: number;
  cursor?: string;
  status?: string;
}): Promise<CursorPage<BetaTester>> {
  const limit = Math.min(options.limit ?? 25, 100);
  let query: FirebaseFirestore.Query = adminFirestore()
    .collection(COLLECTIONS.betaTesters)
    .orderBy("createdAt", "desc")
    .limit(limit + 1);

  if (options.status) {
    query = adminFirestore()
      .collection(COLLECTIONS.betaTesters)
      .where("status", "==", options.status)
      .orderBy("createdAt", "desc")
      .limit(limit + 1);
  }

  const cursorId = decodeCursor(options.cursor);
  if (cursorId) {
    const cursorDoc = await adminFirestore()
      .collection(COLLECTIONS.betaTesters)
      .doc(cursorId)
      .get();
    if (cursorDoc.exists) query = query.startAfter(cursorDoc);
  }

  const snap = await query.get().catch(async () =>
    adminFirestore()
      .collection(COLLECTIONS.betaTesters)
      .limit(limit + 1)
      .get(),
  );

  const docs = snap.docs.slice(0, limit);
  const hasMore = snap.docs.length > limit;
  const items = docs.map((doc) => mapTester(doc.id, doc.data() ?? {}));

  return {
    items,
    nextCursor:
      hasMore && items.length > 0
        ? encodeCursor(items[items.length - 1]!.id)
        : null,
    hasMore,
  };
}

export async function createBetaTester(input: {
  email: string;
  displayName?: string | null;
  uid?: string | null;
  platform: string;
  notes?: string | null;
  actorUid: string;
  actorName: string | null;
  actorRole: string;
  requestId?: string | null;
}): Promise<BetaTester> {
  const email = input.email.trim().toLowerCase();
  const existing = await adminFirestore()
    .collection(COLLECTIONS.betaTesters)
    .where("email", "==", email)
    .limit(1)
    .get()
    .catch(() => null);

  if (existing && !existing.empty) {
    const doc = existing.docs[0]!;
    return mapTester(doc.id, doc.data() ?? {});
  }

  const ref = adminFirestore().collection(COLLECTIONS.betaTesters).doc();
  const payload = {
    id: ref.id,
    email,
    displayName: input.displayName ?? null,
    uid: input.uid ?? null,
    platform: input.platform,
    status: "invited" as const,
    notes: input.notes ?? null,
    invitedBy: input.actorUid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.set(payload);
  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType: "create_beta_tester",
    targetType: "beta_tester",
    targetId: ref.id,
    targetLabel: email,
    description: `Invited beta tester ${email}`,
    requestId: input.requestId ?? null,
  });
  return {
    id: ref.id,
    email,
    displayName: input.displayName ?? null,
    uid: input.uid ?? null,
    platform: input.platform,
    status: "invited",
    notes: input.notes ?? null,
    invitedBy: input.actorUid,
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

export async function patchBetaTester(input: {
  id: string;
  patch: z.infer<typeof betaTesterPatchSchema>;
  actorUid: string;
  actorName: string | null;
  actorRole: string;
  requestId?: string | null;
}): Promise<BetaTester | null> {
  const ref = adminFirestore()
    .collection(COLLECTIONS.betaTesters)
    .doc(input.id);
  const snap = await ref.get();
  if (!snap.exists) return null;
  const previous = mapTester(snap.id, snap.data() ?? {});
  const next = {
    ...(input.patch.status !== undefined
      ? { status: input.patch.status }
      : {}),
    ...(input.patch.displayName !== undefined
      ? { displayName: input.patch.displayName }
      : {}),
    ...(input.patch.platform !== undefined
      ? { platform: input.patch.platform }
      : {}),
    ...(input.patch.notes !== undefined ? { notes: input.patch.notes } : {}),
    ...(input.patch.uid !== undefined ? { uid: input.patch.uid } : {}),
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: input.actorUid,
  };
  await ref.set(next, { merge: true });
  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType: "patch_beta_tester",
    targetType: "beta_tester",
    targetId: input.id,
    targetLabel: previous.email,
    description: `Updated beta tester ${previous.email}`,
    previousStateSnapshot: {
      status: previous.status,
      platform: previous.platform,
    },
    newStateSnapshot: input.patch as Record<string, unknown>,
    requestId: input.requestId ?? null,
  });
  const updated = await ref.get();
  return mapTester(updated.id, updated.data() ?? {});
}
