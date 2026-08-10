import { cookies } from "next/headers";
import type { DecodedIdToken } from "firebase-admin/auth";
import { adminAuth } from "@/lib/firebase/admin";
import {
  getPlatformAdminByUid,
  resolveAdminPermissions,
  touchAdminLogin,
} from "@/lib/platform-admin/repository";
import type { PlatformAdmin } from "@/lib/platform-admin/types";
import {
  adminHasPermission,
  type PlatformPermission,
} from "@/lib/permissions/registry";
import { ADMIN_ERRORS, AdminHttpError } from "@/lib/auth/errors";

export type AdminSessionContext = {
  uid: string;
  email: string | null;
  token: DecodedIdToken;
  admin: PlatformAdmin;
  permissions: PlatformPermission[];
};

export function sessionCookieName(): string {
  return (
    process.env.ADMIN_SESSION_COOKIE_NAME?.trim() ||
    "__sabibom_admin_session"
  );
}

export function sessionExpiresDays(): number {
  const raw = Number(process.env.ADMIN_SESSION_EXPIRES_DAYS ?? "5");
  if (!Number.isFinite(raw) || raw < 1 || raw > 14) return 5;
  return Math.floor(raw);
}

export function sessionCookieOptions(maxAgeSeconds: number) {
  const secure = process.env.NODE_ENV === "production";
  return {
    httpOnly: true,
    secure,
    sameSite: "lax" as const,
    path: "/",
    maxAge: maxAgeSeconds,
  };
}

export async function createSessionCookieFromIdToken(
  idToken: string,
): Promise<{ cookie: string; expiresInMs: number; admin: PlatformAdmin }> {
  const decoded = await adminAuth().verifyIdToken(idToken, true);
  const admin = await getPlatformAdminByUid(decoded.uid);
  if (!admin) {
    throw new AdminHttpError(403, ADMIN_ERRORS.notPlatformAdmin, "not_platform_admin");
  }
  if (admin.status !== "active") {
    throw new AdminHttpError(403, ADMIN_ERRORS.adminDisabled, "admin_disabled");
  }

  const expiresInMs = sessionExpiresDays() * 24 * 60 * 60 * 1000;
  const cookie = await adminAuth().createSessionCookie(idToken, {
    expiresIn: expiresInMs,
  });
  await touchAdminLogin(decoded.uid);
  return { cookie, expiresInMs, admin };
}

export async function clearSessionCookie(): Promise<void> {
  const jar = await cookies();
  jar.set(sessionCookieName(), "", {
    ...sessionCookieOptions(0),
    maxAge: 0,
  });
}

export async function verifyAdminSession(): Promise<AdminSessionContext> {
  const jar = await cookies();
  const session = jar.get(sessionCookieName())?.value;
  if (!session) {
    throw new AdminHttpError(401, ADMIN_ERRORS.unauthenticated, "unauthenticated");
  }

  let decoded: DecodedIdToken;
  try {
    decoded = await adminAuth().verifySessionCookie(session, true);
  } catch {
    throw new AdminHttpError(401, ADMIN_ERRORS.unauthenticated, "unauthenticated");
  }

  const admin = await getPlatformAdminByUid(decoded.uid);
  if (!admin) {
    throw new AdminHttpError(403, ADMIN_ERRORS.notPlatformAdmin, "not_platform_admin");
  }
  if (admin.status !== "active") {
    throw new AdminHttpError(403, ADMIN_ERRORS.adminDisabled, "admin_disabled");
  }

  return {
    uid: decoded.uid,
    email: decoded.email ?? admin.email,
    token: decoded,
    admin,
    permissions: resolveAdminPermissions(admin),
  };
}

export async function requirePlatformAdmin(): Promise<AdminSessionContext> {
  return verifyAdminSession();
}

export async function getCurrentPlatformAdmin(): Promise<PlatformAdmin> {
  const ctx = await requirePlatformAdmin();
  return ctx.admin;
}

export async function requirePlatformPermission(
  permission: PlatformPermission,
): Promise<AdminSessionContext> {
  const ctx = await requirePlatformAdmin();
  if (
    !adminHasPermission(ctx.admin.role, ctx.admin.permissions, permission)
  ) {
    throw new AdminHttpError(403, ADMIN_ERRORS.permissionDenied, "permission_denied");
  }
  return ctx;
}

export async function requireSuperAdmin(): Promise<AdminSessionContext> {
  const ctx = await requirePlatformAdmin();
  if (ctx.admin.role !== "super_admin") {
    throw new AdminHttpError(403, ADMIN_ERRORS.permissionDenied, "permission_denied");
  }
  return ctx;
}

/**
 * Foundation stub for MFA / recent reauth.
 * Blocks when mfaRequired is set until Firebase MFA is enrolled (Checkpoint later).
 */
export async function requireRecentAuthentication(
  options: { allowWithoutMfaEnrollment?: boolean } = {},
): Promise<AdminSessionContext> {
  const ctx = await requirePlatformAdmin();
  if (ctx.admin.mfaRequired && !options.allowWithoutMfaEnrollment) {
    const factorCount =
      typeof ctx.token.firebase?.sign_in_second_factor === "string" ||
      Array.isArray(
        (ctx.token as { firebase?: { sign_in_attributes?: unknown } }).firebase
          ?.sign_in_attributes,
      )
        ? 1
        : 0;
    // Decoded session cookies may not always expose MFA factors; treat
    // mfaRequired as a soft gate that surfaces UI until enrollment is verified.
    if (factorCount < 1 && process.env.ADMIN_ENFORCE_MFA === "true") {
      throw new AdminHttpError(403, ADMIN_ERRORS.mfaRequired, "mfa_required");
    }
  }
  return ctx;
}

/** Soft check used by middleware (no throw). */
export async function peekAdminSession(): Promise<
  | { ok: true; uid: string }
  | { ok: false; reason: "missing" | "invalid" | "not_admin" | "disabled" }
> {
  try {
    const jar = await cookies();
    const session = jar.get(sessionCookieName())?.value;
    if (!session) return { ok: false, reason: "missing" };
    const decoded = await adminAuth().verifySessionCookie(session, true);
    const admin = await getPlatformAdminByUid(decoded.uid);
    if (!admin) return { ok: false, reason: "not_admin" };
    if (admin.status !== "active") return { ok: false, reason: "disabled" };
    return { ok: true, uid: decoded.uid };
  } catch {
    return { ok: false, reason: "invalid" };
  }
}
