"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sha256Id = sha256Id;
exports.eventKey = eventKey;
exports.ledgerId = ledgerId;
exports.notificationId = notificationId;
exports.activityId = activityId;
const node_crypto_1 = require("node:crypto");
function normalized(parts) {
    return parts.map((part) => part.trim()).join("\u001f");
}
function sha256Id(...parts) {
    return (0, node_crypto_1.createHash)("sha256").update(normalized(parts), "utf8").digest("hex");
}
function eventKey(source, businessId, sourceId, transition) {
    return sha256Id("event", source, businessId, sourceId, transition);
}
function ledgerId(eventId, userId) {
    return sha256Id("ledger", eventId, userId);
}
function notificationId(eventId, userId) {
    return sha256Id("notification", eventId, userId);
}
function activityId(eventId) {
    return sha256Id("staff_activity", eventId);
}
//# sourceMappingURL=ids.js.map