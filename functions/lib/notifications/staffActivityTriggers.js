"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onStaffActivityCreated = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const business_1 = require("./business");
const delivery_1 = require("./delivery");
const ids_1 = require("./ids");
const recipients_1 = require("./recipients");
exports.onStaffActivityCreated = (0, firestore_1.onDocumentCreated)("businesses/{businessId}/staff_activity/{activityId}", async (event) => {
    try {
        const activity = event.data?.data();
        if (!activity)
            return;
        const actionType = activity.actionType ?? activity.type;
        if ((0, recipients_1.isApprovalOwnedAction)(actionType))
            return;
        const businessId = event.params.businessId;
        const activityId = event.params.activityId;
        const actorId = (0, business_1.asString)(activity.userId) ?? (0, business_1.asString)(activity.createdBy);
        const targetId = (0, recipients_1.activityTargetId)(activity);
        const branchId = (0, business_1.asString)(activity.branchId) ??
            (0, business_1.asString)(activity.metadata?.branchId);
        const audience = await (0, business_1.loadBusinessAudience)(businessId);
        const recipients = (0, recipients_1.staffObserverRecipients)({
            members: audience.members,
            actorId,
            targetId,
            branchId,
        });
        const rawLabel = (0, business_1.asString)(actionType) ?? "staff_activity";
        const label = rawLabel.replace(/[._]/g, " ");
        const title = "Staff activity";
        const body = `${label.charAt(0).toUpperCase()}${label.slice(1)}.`;
        const id = (0, ids_1.eventKey)("staff_activity", businessId, activityId, "created");
        await (0, delivery_1.deliverMany)(recipients.map((userId) => ({
            eventId: id,
            userId,
            category: "staffActivity",
            type: "staff_activity",
            title,
            body,
            businessId,
            businessName: audience.businessName,
            branchId,
            entityType: "staff_activity",
            entityId: activityId,
            routeName: "teamActivity",
            routeParameters: { businessId, activityId },
        })));
    }
    catch (error) {
        console.error("staff activity notification trigger failed safely", {
            businessId: event.params.businessId,
            activityId: event.params.activityId,
            error: error instanceof Error ? error.message : "unknown",
        });
    }
});
//# sourceMappingURL=staffActivityTriggers.js.map