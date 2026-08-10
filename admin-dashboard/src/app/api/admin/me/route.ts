import { requirePlatformAdmin } from "@/lib/auth/session";
import { jsonError, jsonOk } from "@/lib/auth/http";
import { newRequestId } from "@/lib/auth/errors";

export async function GET() {
  const requestId = newRequestId();
  try {
    const ctx = await requirePlatformAdmin();
    return jsonOk({
      uid: ctx.uid,
      email: ctx.email,
      displayName: ctx.admin.displayName,
      photoUrl: ctx.admin.photoUrl,
      role: ctx.admin.role,
      status: ctx.admin.status,
      permissions: ctx.permissions,
      mfaRequired: ctx.admin.mfaRequired,
      requestId,
    });
  } catch (error) {
    return jsonError(error, requestId);
  }
}
