"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.unauthenticated = unauthenticated;
exports.permissionDenied = permissionDenied;
exports.invalidArgument = invalidArgument;
exports.resourceExhausted = resourceExhausted;
exports.unavailable = unavailable;
exports.failedPrecondition = failedPrecondition;
exports.internal = internal;
const https_1 = require("firebase-functions/v2/https");
function unauthenticated() {
    return new https_1.HttpsError("unauthenticated", "Your session expired. Please sign in again.");
}
function permissionDenied() {
    return new https_1.HttpsError("permission-denied", "You do not have permission to use this feature for this business.");
}
function invalidArgument(message) {
    return new https_1.HttpsError("invalid-argument", message);
}
function resourceExhausted(message) {
    return new https_1.HttpsError("resource-exhausted", message ?? "Too many requests. Please wait and try again.");
}
function unavailable(message) {
    return new https_1.HttpsError("unavailable", message ?? "This service is temporarily unavailable. Please try again.");
}
function failedPrecondition(message) {
    return new https_1.HttpsError("failed-precondition", message);
}
function internal() {
    return new https_1.HttpsError("internal", "Something went wrong. Please try again.");
}
//# sourceMappingURL=errors.js.map