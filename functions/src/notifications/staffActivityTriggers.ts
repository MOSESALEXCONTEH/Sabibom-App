import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {asString, loadBusinessAudience} from "./business";
import {deliverMany} from "./delivery";
import {eventKey} from "./ids";
import {
  activityTargetId,
  isApprovalOwnedAction,
  staffObserverRecipients,
} from "./recipients";

export const onStaffActivityCreated = onDocumentCreated(
  "businesses/{businessId}/staff_activity/{activityId}",
  async (event) => {
    try {
      const activity = event.data?.data();
      if (!activity) return;
      const actionType = activity.actionType ?? activity.type;
      if (isApprovalOwnedAction(actionType)) return;
      const businessId = event.params.businessId;
      const activityId = event.params.activityId;
      const actorId = asString(activity.userId) ?? asString(activity.createdBy);
      const targetId = activityTargetId(activity);
      const branchId = asString(activity.branchId) ??
        asString((activity.metadata as Record<string, unknown> | undefined)?.branchId);
      const audience = await loadBusinessAudience(businessId);
      const recipients = staffObserverRecipients({
        members: audience.members,
        actorId,
        targetId,
        branchId,
      });
      const rawLabel = asString(actionType) ?? "staff_activity";
      const label = rawLabel.replace(/[._]/g, " ");
      const title = "Staff activity";
      const body = `${label.charAt(0).toUpperCase()}${label.slice(1)}.`;
      const id = eventKey("staff_activity", businessId, activityId, "created");
      await deliverMany(recipients.map((userId) => ({
        eventId: id,
        userId,
        category: "staffActivity" as const,
        type: "staff_activity",
        title,
        body,
        businessId,
        businessName: audience.businessName,
        branchId,
        entityType: "staff_activity",
        entityId: activityId,
        routeName: "teamActivity",
        routeParameters: {businessId, activityId},
      })));
    } catch (error) {
      console.error("staff activity notification trigger failed safely", {
        businessId: event.params.businessId,
        activityId: event.params.activityId,
        error: error instanceof Error ? error.message : "unknown",
      });
    }
  },
);
