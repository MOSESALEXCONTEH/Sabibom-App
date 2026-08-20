"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.loadBusinessAudience = loadBusinessAudience;
exports.asString = asString;
exports.asStrings = asStrings;
exports.sameStrings = sameStrings;
const firestore_1 = require("firebase-admin/firestore");
const permissions_1 = require("./permissions");
function text(value) {
    return typeof value === "string" && value.trim() ? value.trim() : undefined;
}
async function loadBusinessAudience(businessId) {
    const db = (0, firestore_1.getFirestore)();
    const businessRef = db.collection("businesses").doc(businessId);
    const [business, members, roles] = await Promise.all([
        businessRef.get(),
        businessRef.collection("members").get(),
        businessRef.collection("roles").get(),
    ]);
    const ownerId = text(business.data()?.ownerId);
    const roleMap = new Map(roles.docs.map((role) => [role.id, role.data()]));
    const resolved = members.docs.map((member) => {
        const data = member.data();
        const roleId = text(data.roleId) ?? text(data.role) ?? "cashier";
        return (0, permissions_1.effectiveMembership)({
            userId: member.id,
            ownerId,
            member: data,
            role: roleMap.get(roleId),
        });
    });
    if (ownerId && !resolved.some((member) => member.userId === ownerId)) {
        resolved.push((0, permissions_1.effectiveMembership)({
            userId: ownerId,
            ownerId,
            member: { status: "active", roleId: "owner", isOwner: true },
        }));
    }
    return {
        ownerId,
        businessName: text(business.data()?.name) ?? "Business",
        members: resolved,
    };
}
function asString(value) {
    return text(value);
}
function asStrings(value) {
    if (!Array.isArray(value))
        return [];
    return value.map(text).filter((item) => item !== undefined);
}
function sameStrings(left, right) {
    const a = [...new Set(asStrings(left))].sort();
    const b = [...new Set(asStrings(right))].sort();
    return a.length === b.length && a.every((item, index) => item === b[index]);
}
//# sourceMappingURL=business.js.map