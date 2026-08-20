import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {asString, asStrings, loadBusinessAudience} from "./business";
import {deliverMany, NotificationContent} from "./delivery";
import {eventKey} from "./ids";
import {approvalRecipients} from "./recipients";

const terminal = new Set(["approved", "rejected", "expired"]);
const labels: Record<string, string> = {
  void_sale: "Void sale",
  void_expense: "Void expense",
  price_override: "Price override",
  large_discount: "Large discount",
  stock_correction: "Stock correction",
  customer_balance_adjustment: "Customer balance adjustment",
  supplier_overpayment: "Supplier overpayment",
  purchase_return: "Purchase return",
};

export function approvalTransition(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): "pending_created" | "approved" | "rejected" | "expired" | undefined {
  if (!after) return undefined;
  const afterStatus = asString(after.status) ?? "pending";
  if (!before) return afterStatus === "pending" ? "pending_created" : undefined;
  const beforeStatus = asString(before.status) ?? "pending";
  if (beforeStatus === afterStatus || beforeStatus !== "pending") return undefined;
  return terminal.has(afterStatus) ? afterStatus as "approved" | "rejected" | "expired" : undefined;
}

export const onApprovalRequestWritten = onDocumentWritten(
  "businesses/{businessId}/approval_requests/{approvalId}",
  async (event) => {
    try {
      const before = event.data?.before.exists ? event.data.before.data() : undefined;
      const after = event.data?.after.exists ? event.data.after.data() : undefined;
      const transition = approvalTransition(before, after);
      if (!transition || !after) return;
      const businessId = event.params.businessId;
      const approvalId = event.params.approvalId;
      const requesterId = asString(after.requestedBy);
      if (!requesterId) return;
      const audience = await loadBusinessAudience(businessId);
      const type = asString(after.type) ?? "approval";
      const action = labels[type] ?? "Sensitive action";
      const branchId = asString(after.branchId) ??
        asString((after.entitySnapshot as Record<string, unknown> | undefined)?.branchId);
      const id = eventKey("approval", businessId, approvalId, transition);
      let recipients: string[];
      let title: string;
      let body: string;
      if (transition === "pending_created") {
        recipients = approvalRecipients({
          members: audience.members,
          requesterId,
          branchId,
          assignedApproverIds: asStrings(after.assignedApproverIds),
        });
        title = "Approval required";
        body = `${action} is waiting for approval.`;
      } else {
        recipients = audience.members.some(
          (member) => member.userId === requesterId && member.active,
        ) ? [requesterId] : [];
        title = transition === "approved" ? "Request approved" :
          transition === "rejected" ? "Request rejected" : "Request expired";
        body = `${action} was ${transition}.`;
      }
      const notifications: NotificationContent[] = recipients.map((userId) => ({
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
        routeParameters: {businessId, approvalId},
        priority: "high",
      }));
      await deliverMany(notifications);
    } catch (error) {
      console.error("approval notification trigger failed safely", {
        businessId: event.params.businessId,
        approvalId: event.params.approvalId,
        error: error instanceof Error ? error.message : "unknown",
      });
    }
  },
);
