import { NextRequest, NextResponse } from "next/server";
import { ZodError } from "zod";
import {
  ADMIN_ERRORS,
  AdminHttpError,
  newRequestId,
} from "@/lib/auth/errors";
import { jsonError, jsonOk } from "@/lib/auth/http";
import type { AdminSessionContext } from "@/lib/auth/session";
import {
  requirePlatformAdmin,
  requirePlatformPermission,
  requireRecentAuthentication,
  requireSuperAdmin,
} from "@/lib/auth/session";
import type { PlatformPermission } from "@/lib/permissions/registry";

type HandlerOptions = {
  permission?: PlatformPermission;
  superAdmin?: boolean;
  recentAuth?: boolean;
};

type HandlerFn = (args: {
  request: NextRequest;
  ctx: AdminSessionContext;
  requestId: string;
  params: Record<string, string>;
}) => Promise<unknown> | unknown;

export function withAdminRoute(options: HandlerOptions, handler: HandlerFn) {
  return async (
    request: NextRequest,
    context?: { params?: Promise<Record<string, string>> | Record<string, string> },
  ) => {
    const requestId = newRequestId();
    try {
      let ctx: AdminSessionContext;
      if (options.superAdmin) {
        ctx = await requireSuperAdmin();
      } else if (options.permission) {
        ctx = await requirePlatformPermission(options.permission);
      } else {
        ctx = await requirePlatformAdmin();
      }
      if (options.recentAuth) {
        ctx = await requireRecentAuthentication();
      }

      const paramsRaw = context?.params;
      const params =
        paramsRaw && typeof (paramsRaw as Promise<unknown>).then === "function"
          ? await (paramsRaw as Promise<Record<string, string>>)
          : ((paramsRaw as Record<string, string> | undefined) ?? {});

      const data = await handler({ request, ctx, requestId, params });
      if (data instanceof NextResponse) return data;
      return jsonOk(data);
    } catch (error) {
      if (error instanceof ZodError) {
        return NextResponse.json(
          {
            error: {
              code: "invalid_argument",
              message: "Invalid request input.",
              requestId,
              details: error.flatten(),
            },
          },
          { status: 400 },
        );
      }
      if (error instanceof AdminHttpError && !error.requestId) {
        return jsonError(
          new AdminHttpError(error.status, error.message, error.code, requestId),
          requestId,
        );
      }
      if (!(error instanceof AdminHttpError)) {
        console.error(`[admin-api] ${requestId}`, error);
        return jsonError(
          new AdminHttpError(500, ADMIN_ERRORS.serverError, "server_error", requestId),
          requestId,
        );
      }
      return jsonError(error, requestId);
    }
  };
}
