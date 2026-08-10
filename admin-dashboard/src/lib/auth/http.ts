import { NextResponse } from "next/server";
import {
  ADMIN_ERRORS,
  AdminHttpError,
  newRequestId,
} from "@/lib/auth/errors";

export function jsonError(error: unknown, fallbackRequestId?: string) {
  const requestId = fallbackRequestId ?? newRequestId();
  if (error instanceof AdminHttpError) {
    const message =
      error.code === "server_error"
        ? `${ADMIN_ERRORS.serverError} Reference: ${error.requestId ?? requestId}`
        : error.message;
    return NextResponse.json(
      {
        error: {
          code: error.code,
          message,
          requestId: error.requestId ?? requestId,
        },
      },
      { status: error.status },
    );
  }

  return NextResponse.json(
    {
      error: {
        code: "server_error",
        message: `${ADMIN_ERRORS.serverError} Reference: ${requestId}`,
        requestId,
      },
    },
    { status: 500 },
  );
}

export function jsonOk<T>(data: T, init?: ResponseInit) {
  return NextResponse.json({ data }, init);
}
