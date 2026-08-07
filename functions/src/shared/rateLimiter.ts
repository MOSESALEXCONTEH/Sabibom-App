import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {resourceExhausted} from "./errors";

type RateLimitOptions = {
  uid: string;
  businessId: string;
  operation: string;
  windowSeconds?: number;
  maxPerWindow?: number;
  dailyMax?: number;
};

/**
 * Simple Firestore-backed rate limiter scoped by user + business + operation.
 */
export async function enforceRateLimit(options: RateLimitOptions): Promise<void> {
  const windowSeconds = options.windowSeconds ?? 60;
  const maxPerWindow = options.maxPerWindow ?? 10;
  const dailyMax = options.dailyMax ?? 200;
  const db = getFirestore();
  const docId = `${options.uid}_${options.businessId}_${options.operation}`;
  const ref = db.collection("function_rate_limits").doc(docId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const data = snap.data() ?? {};
    const windowStartedAt = (data.windowStartedAt as Timestamp | undefined)
      ?.toMillis() ?? now;
    const dayKey = new Date().toISOString().slice(0, 10);
    let windowCount = (data.windowCount as number | undefined) ?? 0;
    let dailyCount = (data.dailyCount as number | undefined) ?? 0;
    let storedDayKey = (data.dayKey as string | undefined) ?? dayKey;

    if (storedDayKey !== dayKey) {
      storedDayKey = dayKey;
      dailyCount = 0;
    }

    if (now - windowStartedAt > windowSeconds * 1000) {
      windowCount = 0;
    }

    if (windowCount >= maxPerWindow || dailyCount >= dailyMax) {
      throw resourceExhausted(
        "Sabi has received too many requests. Please wait and try again.",
      );
    }

    tx.set(
      ref,
      {
        uid: options.uid,
        businessId: options.businessId,
        operation: options.operation,
        windowStartedAt:
          windowCount === 0 ? Timestamp.now() : data.windowStartedAt ?? Timestamp.now(),
        windowCount: windowCount + 1,
        dailyCount: dailyCount + 1,
        dayKey: storedDayKey,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  });
}
