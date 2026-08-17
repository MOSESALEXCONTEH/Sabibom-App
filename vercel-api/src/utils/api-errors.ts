export type ApiErrorCode =
  | "unauthenticated"
  | "permission_denied"
  | "invalid_argument"
  | "branch_required"
  | "plan_limit_reached"
  | "rate_limited"
  | "not_found"
  | "method_not_allowed"
  | "payload_too_large"
  | "unavailable"
  | "internal";

export class ApiError extends Error {
  readonly code: ApiErrorCode;
  readonly status: number;

  constructor(code: ApiErrorCode, message: string, status: number) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

export const errors = {
  unauthenticated: (message = "Your session expired. Please sign in again.") =>
    new ApiError("unauthenticated", message, 401),
  permissionDenied: (
    message = "You do not have permission to use this feature for the selected business.",
  ) => new ApiError("permission_denied", message, 403),
  invalidArgument: (message = "The information entered is invalid.") =>
    new ApiError("invalid_argument", message, 400),
  branchRequired: (message = "Select an active branch and try again.") =>
    new ApiError("branch_required", message, 400),
  planLimitReached: (message = "This feature requires a different plan.") =>
    new ApiError("plan_limit_reached", message, 403),
  rateLimited: (
    message = "Sabi has received too many requests. Please wait and try again.",
  ) => new ApiError("rate_limited", message, 429),
  notFound: (message = "The requested API service could not be found.") =>
    new ApiError("not_found", message, 404),
  methodNotAllowed: (message = "This action is not supported.") =>
    new ApiError("method_not_allowed", message, 405),
  payloadTooLarge: (
    message = "The selected image or request is too large.",
  ) => new ApiError("payload_too_large", message, 413),
  unavailable: (
    message = "Sabi is temporarily unavailable. Please try again.",
  ) => new ApiError("unavailable", message, 503),
  internal: (
    message = "Something went wrong while processing the request.",
  ) => new ApiError("internal", message, 500),
};
