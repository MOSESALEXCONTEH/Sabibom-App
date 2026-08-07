"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAuthenticatedUid = requireAuthenticatedUid;
exports.requireBusinessMember = requireBusinessMember;
exports.requireOwnerOrManager = requireOwnerOrManager;
const firestore_1 = require("firebase-admin/firestore");
const errors_1 = require("../shared/errors");
async function requireAuthenticatedUid(authUid) {
    if (!authUid) {
        throw (0, errors_1.unauthenticated)();
    }
    return authUid;
}
/**
 * Verifies the caller owns or is an active member of the business.
 * Never trust client-supplied businessId alone.
 */
async function requireBusinessMember(uid, businessId) {
    const trimmed = businessId.trim();
    if (!trimmed) {
        throw (0, errors_1.permissionDenied)();
    }
    const db = (0, firestore_1.getFirestore)();
    const businessSnap = await db.collection("businesses").doc(trimmed).get();
    if (!businessSnap.exists) {
        throw (0, errors_1.permissionDenied)();
    }
    const ownerId = businessSnap.data()?.ownerId;
    if (ownerId === uid) {
        return { role: "owner", isOwner: true };
    }
    const memberSnap = await db
        .collection("businesses")
        .doc(trimmed)
        .collection("members")
        .doc(uid)
        .get();
    if (!memberSnap.exists) {
        throw (0, errors_1.permissionDenied)();
    }
    const member = memberSnap.data() ?? {};
    if (member.status !== "active") {
        throw (0, errors_1.permissionDenied)();
    }
    const role = member.role ?? "cashier";
    return { role, isOwner: false };
}
function requireOwnerOrManager(role, isOwner) {
    if (isOwner)
        return;
    if (role === "owner" || role === "manager")
        return;
    throw (0, errors_1.permissionDenied)();
}
//# sourceMappingURL=businessAuthorization.js.map