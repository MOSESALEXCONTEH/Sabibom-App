"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onApprovalRequestWritten = void 0;
exports.approvalTransition = approvalTransition;
const firestore_1 = require("firebase-functions/v2/firestore");
const business_1 = require("./business");
const delivery_1 = require("./delivery");
const ids_1 = require("./ids");
const recipients_1 = require("./recipients");
const terminal = new Set(["approved", "rejected", "expired"]);
const labels = {
    void_sale: "Void sale",
    void_expense: "Void expense",
    price_override: "Price override",
    large_discount: "Large discount",
    stock_correction: "Stock correction",
    customer_balance_adjustment: "Customer balance adjustment",
    supplier_overpayment: "Supplier overpayment",
    purchase_return: "Purchase return",
};
function approvalTransition(before, after) {
    if (!after)
        return undefined;
    const afterStatus = (0, business_1.asString)(after.status) ?? "pending";
    if (!before)
        return afterStatus === "pending" ? "pending_created" : undefined;
    const beforeStatus = (0, business_1.asString)(before.status) ?? "pending";
    if (beforeStatus === afterStatus || beforeStatus !== "pending")
        return undefined;
    return terminal.has(afterStatus) ? afterStatus : undefined;
}
exports.onApprovalRequestWritten = (0, firestore_1.onDocumentWritten)("businesses/{businessId}/approval_requests/{approvalId}", async (event) => {
    try {
        const before = event.data?.before.exists ? event.data.before.data() : undefined;
        const after = event.data?.after.exists ? event.data.after.data() : undefined;
        const transition = approvalTransition(before, after);
        if (!transition || !after)
            return;
        const businessId = event.params.businessId;
        const approvalId = event.params.approvalId;
        const requesterId = (0, business_1.asString)(after.requestedBy);
        if (!requesterId)
            return;
        const audience = await (0, business_1.loadBusinessAudience)(businessId);
        const type = (0, business_1.asString)(after.type) ?? "approval";
        const action = labels[type] ?? "Sensitive action";
        const branchId = (0, business_1.asString)(after.branchId) ??
            (0, business_1.asString)(after.entitySnapshot?.branchId);
        const id = (0, ids_1.eventKey)("approval", businessId, approvalId, transition);
        let recipients;
        let title;
        let body;
        if (transition === "pending_created") {
            recipients = (0, recipients_1.approvalRecipients)({
                members: audience.members,
                requesterId,
                branchId,
                assignedApproverIds: (0, business_1.asStrings)(after.assignedApproverIds),
            });
            title = "Approval required";
            body = `${action} is waiting for approval.`;
        }
        else {
            recipients = audience.members.some((member) => member.userId === requesterId && member.active) ? [requesterId] : [];
            title = transition === "approved" ? "Request approved" :
                transition === "rejected" ? "Request rejected" : "Request expired";
            body = `${action} was ${transition}.`;
        }
        const notifications = recipients.map((userId) => ({
            eventId: id,
            userId,
            category: "approval",
            type: transition === "pending_created" ? "approval_requested" :
                `approval_${transition}`,
            title,
            body,
            businessId,
            businessName: audience.businessName,
            branchId,
            entityType: "approval_request",
            entityId: approvalId,
            routeName: "approvalDetails",
            routeParameters: { businessId, approvalId },
            priority: "high",
        }));
        await (0, delivery_1.deliverMany)(notifications);
    }
    catch (error) {
        console.error("approval notification trigger failed safely", {
            businessId: event.params.businessId,
            approvalId: event.params.approvalId,
            error: error instanceof Error ? error.message : "unknown",
        });
    }
});
//# sourceMappingURL=approvalTriggers.js.map