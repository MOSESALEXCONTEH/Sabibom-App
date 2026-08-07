import {HttpsError} from "firebase-functions/v2/https";

export function unauthenticated(): HttpsError {
  return new HttpsError(
    "unauthenticated",
    "Your session expired. Please sign in again.",
  );
}

export function permissionDenied(): HttpsError {
  return new HttpsError(
    "permission-denied",
    "You do not have permission to use this feature for this business.",
  );
}

export function invalidArgument(message: string): HttpsError {
  return new HttpsError("invalid-argument", message);
}

export function resourceExhausted(message?: string): HttpsError {
  return new HttpsError(
    "resource-exhausted",
    message ?? "Too many requests. Please wait and try again.",
  );
}

export function unavailable(message?: string): HttpsError {
  return new HttpsError(
    "unavailable",
    message ?? "This service is temporarily unavailable. Please try again.",
  );
}

export function failedPrecondition(message: string): HttpsError {
  return new HttpsError("failed-precondition", message);
}

export function internal(): HttpsError {
  return new HttpsError(
    "internal",
    "Something went wrong. Please try again.",
  );
}
