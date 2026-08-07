"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.enforceRateLimit = enforceRateLimit;
const firestore_1 = require("firebase-admin/firestore");
const errors_1 = require("./errors");
/**
 * Simple Firestore-backed rate limiter scoped by user + business + operation.
 */
async function enforceRateLimit(options) {
    const windowSeconds = options.windowSeconds ?? 60;
    const maxPerWindow = options.maxPerWindow ?? 10;
    const dailyMax = options.dailyMax ?? 200;
    const db = (0, firestore_1.getFirestore)();
    const docId = `${options.uid}_${options.businessId}_${options.operation}`;
    const ref = db.collection("function_rate_limits").doc(docId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const now = Date.now();
        const data = snap.data() ?? {};
        const windowStartedAt = data.windowStartedAt
            ?.toMillis() ?? now;
        const dayKey = new Date().toISOString().slice(0, 10);
        let windowCount = data.windowCount ?? 0;
        let dailyCount = data.dailyCount ?? 0;
        let storedDayKey = data.dayKey ?? dayKey;
        if (storedDayKey !== dayKey) {
            storedDayKey = dayKey;
            dailyCount = 0;
        }
        if (now - windowStartedAt > windowSeconds * 1000) {
            windowCount = 0;
        }
        if (windowCount >= maxPerWindow || dailyCount >= dailyMax) {
            throw (0, errors_1.resourceExhausted)("Sabi has received too many requests. Please wait and try again.");
        }
        tx.set(ref, {
            uid: options.uid,
            businessId: options.businessId,
            operation: options.operation,
            windowStartedAt: windowCount === 0 ? firestore_1.Timestamp.now() : data.windowStartedAt ?? firestore_1.Timestamp.now(),
            windowCount: windowCount + 1,
            dailyCount: dailyCount + 1,
            dayKey: storedDayKey,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
//# sourceMappingURL=rateLimiter.js.map