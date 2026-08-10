import { z } from "zod";
import {
  PLATFORM_ADMIN_STATUSES,
  PLATFORM_PERMISSIONS,
  PLATFORM_ROLES,
  type PlatformAdminStatus,
  type PlatformPermission,
  type PlatformRole,
} from "@/lib/permissions/registry";

export const platformAdminSchema = z.object({
  uid: z.string().min(1),
  displayName: z.string().nullable().optional(),
  email: z.string().email().nullable().optional(),
  photoUrl: z.string().url().nullable().optional(),
  role: z.enum(PLATFORM_ROLES),
  permissions: z.array(z.enum(PLATFORM_PERMISSIONS)).default([]),
  status: z.enum(PLATFORM_ADMIN_STATUSES),
  createdBy: z.string().nullable().optional(),
  createdAt: z.unknown().optional(),
  updatedBy: z.string().nullable().optional(),
  updatedAt: z.unknown().optional(),
  lastLoginAt: z.unknown().optional(),
  lastActiveAt: z.unknown().optional(),
  mfaRequired: z.boolean().default(false),
  notes: z.string().nullable().optional(),
});

export type PlatformAdmin = {
  uid: string;
  displayName: string | null;
  email: string | null;
  photoUrl: string | null;
  role: PlatformRole;
  permissions: PlatformPermission[];
  status: PlatformAdminStatus;
  createdBy: string | null;
  createdAt: Date | null;
  updatedBy: string | null;
  updatedAt: Date | null;
  lastLoginAt: Date | null;
  lastActiveAt: Date | null;
  mfaRequired: boolean;
  notes: string | null;
};

export type PlatformAdminActivity = {
  id: string;
  adminUid: string;
  adminName: string | null;
  adminRole: PlatformRole | "bootstrap_script" | string;
  actionType: string;
  targetType: string;
  targetId: string;
  targetLabel: string | null;
  description: string;
  reason: string | null;
  metadata: Record<string, unknown> | null;
  requestId: string | null;
  createdAt: Date | null;
};

function asDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value === "object" && value !== null && "toDate" in value) {
    const maybe = value as { toDate: () => Date };
    try {
      return maybe.toDate();
    } catch {
      return null;
    }
  }
  if (typeof value === "string" || typeof value === "number") {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

export function platformAdminFromFirestore(
  uid: string,
  data: Record<string, unknown>,
): PlatformAdmin {
  const role = (data.role as PlatformRole) ?? "read_only_admin";
  const status = (data.status as PlatformAdminStatus) ?? "disabled";
  const permissions = Array.isArray(data.permissions)
    ? (data.permissions.filter(
        (p): p is PlatformPermission =>
          typeof p === "string" &&
          (PLATFORM_PERMISSIONS as readonly string[]).includes(p),
      ) as PlatformPermission[])
    : [];

  return {
    uid,
    displayName: typeof data.displayName === "string" ? data.displayName : null,
    email: typeof data.email === "string" ? data.email : null,
    photoUrl: typeof data.photoUrl === "string" ? data.photoUrl : null,
    role,
    permissions,
    status,
    createdBy: typeof data.createdBy === "string" ? data.createdBy : null,
    createdAt: asDate(data.createdAt),
    updatedBy: typeof data.updatedBy === "string" ? data.updatedBy : null,
    updatedAt: asDate(data.updatedAt),
    lastLoginAt: asDate(data.lastLoginAt),
    lastActiveAt: asDate(data.lastActiveAt),
    mfaRequired: data.mfaRequired === true,
    notes: typeof data.notes === "string" ? data.notes : null,
  };
}
