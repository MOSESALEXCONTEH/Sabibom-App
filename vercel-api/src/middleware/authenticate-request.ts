import type {VercelRequest} from "@vercel/node";
import {adminAuth} from "../config/firebase-admin";
import {errors} from "../utils/api-errors";
import type {AuthenticatedIdentity} from "../types/authenticated-request";

export async function authenticateRequest(
  req: VercelRequest,
): Promise<AuthenticatedIdentity> {
  const header = req.headers.authorization;
  if (!header || typeof header !== "string") {
    throw errors.unauthenticated();
  }

  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match?.[1]) {
    throw errors.unauthenticated();
  }

  const token = match[1].trim();
  if (!token) {
    throw errors.unauthenticated();
  }

  try {
    const decoded = await adminAuth().verifyIdToken(token);
    if (!decoded.uid) {
      throw errors.unauthenticated();
    }
    return {uid: decoded.uid, email: decoded.email};
  } catch (error) {
    if (error && typeof error === "object" && "status" in error) {
      throw error;
    }
    const code =
      error && typeof error === "object" && "code" in error
        ? String((error as {code?: unknown}).code ?? "")
        : "";
    const message =
      error instanceof Error ? error.message : "token verification failed";
    console.error("[sabibom-api] verifyIdToken failed", {code, message});
    if (
      code.includes("invalid-credential") ||
      message.toLowerCase().includes("private key") ||
      message.toLowerCase().includes("credential")
    ) {
      throw errors.unavailable(
        "Sabi is temporarily unavailable. Please try again shortly.",
      );
    }
    throw errors.unauthenticated();
  }
}
