import { FieldValue } from "firebase-admin/firestore";
import { adminFirestore } from "@/lib/firebase/admin";
import { ADMIN_ERRORS, AdminHttpError } from "@/lib/auth/errors";
import { COLLECTIONS } from "@/lib/platform/collections";

type RateLimitOptions = {
  key: string;
  limit: number;
  windowMs: number;
};

/**
 * Simple Firestore-backed rate limiter for sensitive admin writes.
 * Fail-open on storage errors so ops are not bricked by a transient outage.
 */
export async function enforceRateLimit(options: RateLimitOptions): Promise<void> {
  const { key, limit, windowMs } = options;
  const now = Date.now();
  const windowStart = now - windowMs;
  const docId = `admin_rl_${key.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 120)}`;
  const ref = adminFirestore().collection(COLLECTIONS.apiRateLimits).doc(docId);

  try {
    await adminFirestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.data() ?? {};
      const timestamps = Array.isArray(data.timestamps)
        ? (data.timestamps as number[]).filter((t) => typeof t === "number" && t > windowStart)
        : [];
      if (timestamps.length >= limit) {
        throw new AdminHttpError(429, ADMIN_ERRORS.rateLimited, "rate_limited");
      }
      timestamps.push(now);
      tx.set(
        ref,
        {
          key,
          timestamps,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
  } catch (error) {
    if (error instanceof AdminHttpError) throw error;
    // Fail open — do not block admin ops on rate-limit storage failure.
  }
}
