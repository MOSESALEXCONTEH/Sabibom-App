import { FieldValue } from "firebase-admin/firestore";
import { adminAuth, adminFirestore } from "@/lib/firebase/admin";
import { ADMIN_ERRORS, AdminHttpError } from "@/lib/auth/errors";
import {
  adminHasPermission,
  permissionsForRole,
  type PlatformPermission,
  type PlatformRole,
} from "@/lib/permissions/registry";
import {
  platformAdminFromFirestore,
  type PlatformAdmin,
  type PlatformAdminActivity,
} from "@/lib/platform-admin/types";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS } from "@/lib/platform/collections";
import {
  decodeCursor,
  encodeCursor,
  type CursorPage,
} from "@/lib/api/pagination";

export const PLATFORM_ADMINS_COLLECTION = COLLECTIONS.platformAdmins;
export const PLATFORM_ADMIN_ACTIVITY_COLLECTION =
  COLLECTIONS.platformAdminActivity;

export async function getPlatformAdminByUid(
  uid: string,
): Promise<PlatformAdmin | null> {
  if (!uid.trim()) return null;
  const snap = await adminFirestore()
    .collection(PLATFORM_ADMINS_COLLECTION)
    .doc(uid)
    .get();
  if (!snap.exists) return null;
  return platformAdminFromFirestore(uid, snap.data() ?? {});
}

export function resolveAdminPermissions(
  admin: PlatformAdmin,
): PlatformPermission[] {
  return permissionsForRole(admin.role, admin.permissions);
}

export async function touchAdminLogin(uid: string): Promise<void> {
  await adminFirestore()
    .collection(PLATFORM_ADMINS_COLLECTION)
    .doc(uid)
    .set(
      {
        lastLoginAt: FieldValue.serverTimestamp(),
        lastActiveAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

export async function writeAdminActivity(input: {
  adminUid: string;
  adminName?: string | null;
  adminRole: string;
  actionType: string;
  targetType: string;
  targetId: string;
  targetLabel?: string | null;
  description: string;
  reason?: string | null;
  metadata?: Record<string, unknown> | null;
  previousStateSnapshot?: Record<string, unknown> | null;
  newStateSnapshot?: Record<string, unknown> | null;
  requestId?: string | null;
}): Promise<string> {
  const ref = adminFirestore()
    .collection(PLATFORM_ADMIN_ACTIVITY_COLLECTION)
    .doc();
  await ref.set({
    id: ref.id,
    adminUid: input.adminUid,
    adminName: input.adminName ?? null,
    adminRole: input.adminRole,
    actionType: input.actionType,
    targetType: input.targetType,
    targetId: input.targetId,
    targetLabel: input.targetLabel ?? null,
    description: input.description,
    reason: input.reason ?? null,
    metadata: input.metadata ?? null,
    previousStateSnapshot: input.previousStateSnapshot ?? null,
    newStateSnapshot: input.newStateSnapshot ?? null,
    requestId: input.requestId ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return ref.id;
}

export async function listPlatformAdmins(options: {
  limit?: number;
  cursor?: string;
  status?: string;
}): Promise<CursorPage<PlatformAdmin>> {
  const limit = Math.min(options.limit ?? 25, 100);
  let query = adminFirestore()
    .collection(PLATFORM_ADMINS_COLLECTION)
    .orderBy("createdAt", "desc")
    .limit(limit + 1);

  const cursorId = decodeCursor(options.cursor);
  if (cursorId) {
    const cursorDoc = await adminFirestore()
      .collection(PLATFORM_ADMINS_COLLECTION)
      .doc(cursorId)
      .get();
    if (cursorDoc.exists) {
      query = query.startAfter(cursorDoc);
    }
  }

  const snap = await query.get().catch(async () =>
    adminFirestore()
      .collection(PLATFORM_ADMINS_COLLECTION)
      .limit(limit + 1)
      .get(),
  );

  let items = snap.docs.map((doc) =>
    platformAdminFromFirestore(doc.id, doc.data() ?? {}),
  );
  if (options.status) {
    items = items.filter((a) => a.status === options.status);
  }
  const hasMore = items.length > limit;
  items = items.slice(0, limit);
  const nextCursor =
    hasMore && items.length > 0
      ? encodeCursor(items[items.length - 1]!.uid)
      : null;
  return { items, nextCursor, hasMore };
}

export async function countActiveSuperAdmins(): Promise<number> {
  const snap = await adminFirestore()
    .collection(PLATFORM_ADMINS_COLLECTION)
    .where("role", "==", "super_admin")
    .where("status", "==", "active")
    .get();
  return snap.size;
}

export async function createPlatformAdmin(input: {
  uid: string;
  role: PlatformRole;
  permissions?: PlatformPermission[];
  mfaRequired?: boolean;
  notes?: string | null;
  actor: PlatformAdmin;
  requestId?: string;
}): Promise<PlatformAdmin> {
  if (
    !adminHasPermission(
      input.actor.role,
      input.actor.permissions,
      "manage_platform_admins",
    )
  ) {
    throw new AdminHttpError(403, ADMIN_ERRORS.permissionDenied, "permission_denied");
  }

  if (input.role === "super_admin" && input.actor.role !== "super_admin") {
    throw new AdminHttpError(403, ADMIN_ERRORS.permissionDenied, "permission_denied");
  }

  const existing = await getPlatformAdminByUid(input.uid);
  if (existing && existing.status !== "removed") {
    throw new AdminHttpError(
      409,
      ADMIN_ERRORS.conflict,
      "invalid_argument",
    );
  }

  let authUser;
  try {
    authUser = await adminAuth().getUser(input.uid);
  } catch {
    throw new AdminHttpError(
      404,
      ADMIN_ERRORS.recordUnavailable,
      "invalid_argument",
    );
  }

  const permissions =
    input.role === "custom"
      ? (input.permissions ?? []).filter((p) =>
          adminHasPermission(input.actor.role, input.actor.permissions, p) ||
          input.actor.role === "super_admin",
        )
      : permissionsForRole(input.role, input.permissions ?? []);

  if (input.actor.role !== "super_admin") {
    for (const p of permissions) {
      if (!adminHasPermission(input.actor.role, input.actor.permissions, p)) {
        throw new AdminHttpError(
          403,
          ADMIN_ERRORS.permissionDenied,
          "permission_denied",
        );
      }
    }
  }

  const doc = {
    uid: input.uid,
    displayName: authUser.displayName ?? null,
    email: authUser.email ?? null,
    photoUrl: authUser.photoURL ?? null,
    role: input.role,
    permissions,
    status: "active" as const,
    createdBy: input.actor.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedBy: input.actor.uid,
    updatedAt: FieldValue.serverTimestamp(),
    mfaRequired: input.mfaRequired === true,
    notes: input.notes ?? null,
  };

  await adminFirestore()
    .collection(PLATFORM_ADMINS_COLLECTION)
    .doc(input.uid)
    .set(doc, { merge: false });

  await writeAdminActivity({
    adminUid: input.actor.uid,
    adminName: input.actor.displayName,
    adminRole: input.actor.role,
    actionType: "admin_created",
    targetType: "platform_admin",
    targetId: input.uid,
    targetLabel: authUser.email ?? input.uid,
    description: `Created platform admin with role ${input.role}`,
    newStateSnapshot: {
      role: input.role,
      permissions,
      status: "active",
      mfaRequired: doc.mfaRequired,
    },
    requestId: input.requestId ?? null,
  });

  return (await getPlatformAdminByUid(input.uid))!;
}

export async function updatePlatformAdmin(input: {
  uid: string;
  role?: PlatformRole;
  permissions?: PlatformPermission[];
  mfaRequired?: boolean;
  notes?: string | null;
  status?: PlatformAdmin["status"];
  actor: PlatformAdmin;
  reason?: string | null;
  requestId?: string;
}): Promise<PlatformAdmin> {
  const target = await getPlatformAdminByUid(input.uid);
  if (!target) {
    throw new AdminHttpError(
      404,
      ADMIN_ERRORS.recordUnavailable,
      "invalid_argument",
    );
  }

  const nextRole = input.role ?? target.role;
  const nextStatus = input.status ?? target.status;

  if (nextRole === "super_admin" && input.actor.role !== "super_admin") {
    throw new AdminHttpError(403, ADMIN_ERRORS.permissionDenied, "permission_denied");
  }

  const demotingLastSuper =
    target.role === "super_admin" &&
    target.status === "active" &&
    (nextRole !== "super_admin" ||
      nextStatus === "disabled" ||
      nextStatus === "suspended" ||
      nextStatus === "removed");

  if (demotingLastSuper) {
    const count = await countActiveSuperAdmins();
    if (count <= 1) {
      throw new AdminHttpError(
        409,
        "Cannot remove or demote the last active super admin.",
        "invalid_argument",
      );
    }
  }

  if (
    input.actor.uid === input.uid &&
    demotingLastSuper &&
    (await countActiveSuperAdmins()) <= 1
  ) {
    throw new AdminHttpError(
      409,
      "Cannot remove or demote the last active super admin.",
      "invalid_argument",
    );
  }

  let nextPermissions = target.permissions;
  if (input.permissions || input.role) {
    nextPermissions =
      nextRole === "custom"
        ? (input.permissions ?? target.permissions)
        : permissionsForRole(nextRole, input.permissions ?? []);
    if (input.actor.role !== "super_admin") {
      for (const p of nextPermissions) {
        if (!adminHasPermission(input.actor.role, input.actor.permissions, p)) {
          throw new AdminHttpError(
            403,
            ADMIN_ERRORS.permissionDenied,
            "permission_denied",
          );
        }
      }
    }
  }

  const patch: Record<string, unknown> = {
    updatedBy: input.actor.uid,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (input.role) patch.role = input.role;
  if (input.permissions || input.role) patch.permissions = nextPermissions;
  if (typeof input.mfaRequired === "boolean") patch.mfaRequired = input.mfaRequired;
  if (input.notes !== undefined) patch.notes = input.notes;
  if (input.status) patch.status = input.status;

  await adminFirestore()
    .collection(PLATFORM_ADMINS_COLLECTION)
    .doc(input.uid)
    .set(patch, { merge: true });

  const actionType =
    input.status === "disabled"
      ? "admin_disabled"
      : input.status === "suspended"
        ? "admin_suspended"
        : input.status === "removed"
          ? "admin_removed"
          : input.role
            ? "admin_role_changed"
            : "admin_updated";

  await writeAdminActivity({
    adminUid: input.actor.uid,
    adminName: input.actor.displayName,
    adminRole: input.actor.role,
    actionType,
    targetType: "platform_admin",
    targetId: input.uid,
    targetLabel: target.email,
    description: `Updated platform admin ${input.uid}`,
    reason: input.reason ?? null,
    previousStateSnapshot: {
      role: target.role,
      permissions: target.permissions,
      status: target.status,
      mfaRequired: target.mfaRequired,
    },
    newStateSnapshot: {
      role: nextRole,
      permissions: nextPermissions,
      status: nextStatus,
      mfaRequired:
        typeof input.mfaRequired === "boolean"
          ? input.mfaRequired
          : target.mfaRequired,
    },
    requestId: input.requestId ?? null,
  });

  return (await getPlatformAdminByUid(input.uid))!;
}

export async function listAdminActivity(options: {
  limit?: number;
  cursor?: string;
}): Promise<CursorPage<PlatformAdminActivity>> {
  const limit = Math.min(options.limit ?? 25, 100);
  let query = adminFirestore()
    .collection(PLATFORM_ADMIN_ACTIVITY_COLLECTION)
    .orderBy("createdAt", "desc")
    .limit(limit + 1);

  const cursorId = decodeCursor(options.cursor);
  if (cursorId) {
    const cursorDoc = await adminFirestore()
      .collection(PLATFORM_ADMIN_ACTIVITY_COLLECTION)
      .doc(cursorId)
      .get();
    if (cursorDoc.exists) query = query.startAfter(cursorDoc);
  }

  const snap = await query.get().catch(async () =>
    adminFirestore()
      .collection(PLATFORM_ADMIN_ACTIVITY_COLLECTION)
      .limit(limit + 1)
      .get(),
  );

  const docs = snap.docs.slice(0, limit);
  const hasMore = snap.docs.length > limit;
  const items: PlatformAdminActivity[] = docs.map((doc) => {
    const data = doc.data() ?? {};
    return {
      id: doc.id,
      adminUid: typeof data.adminUid === "string" ? data.adminUid : "",
      adminName: typeof data.adminName === "string" ? data.adminName : null,
      adminRole: typeof data.adminRole === "string" ? data.adminRole : "",
      actionType: typeof data.actionType === "string" ? data.actionType : "",
      targetType: typeof data.targetType === "string" ? data.targetType : "",
      targetId: typeof data.targetId === "string" ? data.targetId : "",
      targetLabel:
        typeof data.targetLabel === "string" ? data.targetLabel : null,
      description:
        typeof data.description === "string" ? data.description : "",
      reason: typeof data.reason === "string" ? data.reason : null,
      metadata:
        data.metadata && typeof data.metadata === "object"
          ? (data.metadata as Record<string, unknown>)
          : null,
      requestId: typeof data.requestId === "string" ? data.requestId : null,
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

export async function resolveFirebaseUserByEmail(email: string) {
  try {
    return await adminAuth().getUserByEmail(email.trim());
  } catch {
    return null;
  }
}
