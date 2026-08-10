import { describe, expect, it } from "vitest";
import { AdminHttpError, ADMIN_ERRORS } from "@/lib/auth/errors";

describe("admin errors", () => {
  it("uses sanitized permission denied message", () => {
    const err = new AdminHttpError(
      403,
      ADMIN_ERRORS.permissionDenied,
      "permission_denied",
    );
    expect(err.status).toBe(403);
    expect(err.message).toBe(
      "You do not have permission to perform this action.",
    );
  });

  it("marks missing session as unauthenticated", () => {
    const err = new AdminHttpError(
      401,
      ADMIN_ERRORS.unauthenticated,
      "unauthenticated",
    );
    expect(err.code).toBe("unauthenticated");
  });
});
