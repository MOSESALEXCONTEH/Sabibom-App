import {adminFirestore} from "../../config/firebase-admin";
import type {
  BusinessMembership,
  BusinessPermission,
} from "../../types/authenticated-request";
import {errors} from "../../utils/api-errors";
import {
  membershipHasPermission,
  resolvePermissions,
  type AppPermissionCode,
  type ResolvedMembership,
} from "./permissions";

/** Map legacy coarse permissions to Phase 8 codes. */
function mapLegacyPermission(
  permission: BusinessPermission | AppPermissionCode,
): AppPermissionCode {
  switch (permission) {
    case "use_sabi":
      return "use_sabi";
    case "read_business_data":
      return "ask_sabi_business_questions";
    case "edit_business_profile":
      return "edit_business_settings";
    case "upload_business_logo":
      return "edit_business_branding";
    default:
      return permission as AppPermissionCode;
  }
}

export async function loadMembership(options: {
  uid: string;
  businessId: string;
}): Promise<ResolvedMembership> {
  const businessId = options.businessId.trim();
  if (!businessId) throw errors.permissionDenied();

  const db = adminFirestore();
  const businessSnap = await db.collection("businesses").doc(businessId).get();
  if (!businessSnap.exists) throw errors.permissionDenied();

  const data = businessSnap.data() ?? {};
  if (data.deleted === true || data.status === "disabled") {
    throw errors.permissionDenied();
  }

  const ownerId = data.ownerId as string | undefined;
  if (ownerId === options.uid) {
    return {
      role: "owner",
      roleId: "owner",
      isOwner: true,
      status: "active",
      permissions: resolvePermissions({isOwner: true}),
    };
  }

  const memberSnap = await db
    .collection("businesses")
    .doc(businessId)
    .collection("members")
    .doc(options.uid)
    .get();

  if (!memberSnap.exists) throw errors.permissionDenied();
  const member = memberSnap.data() ?? {};
  if (member.status !== "active") throw errors.permissionDenied();

  const roleId =
    (member.roleId as string | undefined) ||
    (member.role as string | undefined) ||
    "cashier";

  return {
    role: roleId,
    roleId,
    isOwner: member.isOwner === true || roleId === "owner",
    status: "active",
    permissions: resolvePermissions({
      isOwner: member.isOwner === true || roleId === "owner",
      role: member.role as string | undefined,
      roleId,
      permissions: member.permissions,
    }),
  };
}

export async function requireBusinessAccess(options: {
  uid: string;
  businessId: string;
  requiredPermission: BusinessPermission | AppPermissionCode;
}): Promise<BusinessMembership> {
  const membership = await loadMembership(options);
  const required = mapLegacyPermission(options.requiredPermission);
  if (!membershipHasPermission(membership, required)) {
    throw errors.permissionDenied();
  }
  return {
    role: membership.role,
    isOwner: membership.isOwner,
  };
}

/** Active owner/member only — used for soft-gated uploads like feedback screenshots. */
export async function requireActiveMembership(options: {
  uid: string;
  businessId: string;
}): Promise<BusinessMembership> {
  const membership = await loadMembership(options);
  return {
    role: membership.role,
    isOwner: membership.isOwner,
  };
}

export async function requireAppPermission(options: {
  uid: string;
  businessId: string;
  permission: AppPermissionCode;
}): Promise<ResolvedMembership> {
  const membership = await loadMembership(options);
  if (!membershipHasPermission(membership, options.permission)) {
    throw errors.permissionDenied();
  }
  return membership;
}

export async function countActiveOwners(businessId: string): Promise<number> {
  const db = adminFirestore();
  const snap = await db
    .collection("businesses")
    .doc(businessId)
    .collection("members")
    .where("status", "==", "active")
    .get();
  let count = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.isOwner === true || d.role === "owner" || d.roleId === "owner") {
      count += 1;
    }
  }
  if (count === 0) {
    const biz = await db.collection("businesses").doc(businessId).get();
    const ownerId = biz.data()?.ownerId as string | undefined;
    if (ownerId && snap.docs.some((d) => d.id === ownerId)) return 1;
  }
  return count;
}
