import { cookies } from "next/headers";
import { NextRequest } from "next/server";
import { z } from "zod";
import {
  clearSessionCookie,
  createSessionCookieFromIdToken,
  sessionCookieName,
  sessionCookieOptions,
} from "@/lib/auth/session";
import { jsonError, jsonOk } from "@/lib/auth/http";
import { newRequestId } from "@/lib/auth/errors";
import { resolveAdminPermissions } from "@/lib/platform-admin/repository";

const createSessionSchema = z.object({
  idToken: z.string().min(20).max(4096),
});

export async function POST(request: NextRequest) {
  const requestId = newRequestId();
  try {
    const body = createSessionSchema.parse(await request.json());
    const { cookie, expiresInMs, admin } =
      await createSessionCookieFromIdToken(body.idToken);
    const jar = await cookies();
    jar.set(
      sessionCookieName(),
      cookie,
      sessionCookieOptions(Math.floor(expiresInMs / 1000)),
    );

    return jsonOk({
      uid: admin.uid,
      role: admin.role,
      status: admin.status,
      permissions: resolveAdminPermissions(admin),
      mfaRequired: admin.mfaRequired,
      requestId,
    });
  } catch (error) {
    return jsonError(error, requestId);
  }
}

export async function DELETE() {
  const requestId = newRequestId();
  try {
    await clearSessionCookie();
    return jsonOk({ signedOut: true, requestId });
  } catch (error) {
    return jsonError(error, requestId);
  }
}
