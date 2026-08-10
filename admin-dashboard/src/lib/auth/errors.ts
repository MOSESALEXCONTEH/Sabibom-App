export const ADMIN_ERRORS = {
  unauthenticated: "Your admin session expired. Sign in again.",
  notPlatformAdmin:
    "This account does not have access to the SabiBom Admin Dashboard.",
  permissionDenied: "You do not have permission to perform this action.",
  adminDisabled: "Your platform-admin access has been disabled.",
  recordUnavailable: "This record is no longer available.",
  conflict:
    "This record changed while you were working. Refresh and try again.",
  rateLimited: "Too many requests. Wait and try again.",
  serverError: "The operation could not be completed.",
  mfaRequired:
    "Multi-factor authentication is required for this admin account before continuing.",
} as const;

export class AdminHttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly code:
      | "unauthenticated"
      | "not_platform_admin"
      | "permission_denied"
      | "admin_disabled"
      | "mfa_required"
      | "invalid_argument"
      | "rate_limited"
      | "server_error" = "server_error",
    public readonly requestId?: string,
  ) {
    super(message);
    this.name = "AdminHttpError";
  }
}

export function newRequestId(): string {
  return `req_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}
