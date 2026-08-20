"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const approvalTriggers_1 = require("./approvalTriggers");
const delivery_1 = require("./delivery");
const ids_1 = require("./ids");
const permissions_1 = require("./permissions");
const policy_1 = require("./policy");
const recipients_1 = require("./recipients");
(0, node_test_1.default)("business preferences win, legacy is fallback, defaults allow", () => {
    const business = (0, policy_1.resolveNotificationPolicy)({ approvalEnabled: false, inAppEnabled: true }, { approvalEnabled: true, pushEnabled: false }, "approval");
    strict_1.default.equal(business.categoryEnabled, false);
    strict_1.default.equal(business.pushEnabled, true);
    const legacy = (0, policy_1.resolveNotificationPolicy)(undefined, { team: false }, "staffActivity");
    strict_1.default.equal(legacy.categoryEnabled, false);
    const defaults = (0, policy_1.resolveNotificationPolicy)(undefined, undefined, "approval");
    strict_1.default.deepEqual([defaults.inAppEnabled, defaults.pushEnabled, defaults.categoryEnabled], [true, true, true]);
});
(0, node_test_1.default)("in-app and push are independent and quiet hours suppress push only", () => {
    const policy = (0, policy_1.resolveNotificationPolicy)({
        inAppEnabled: true, pushEnabled: true, approvalEnabled: true,
        quietHoursEnabled: true, quietHoursStart: "22:00", quietHoursEnd: "07:00",
        timezone: "UTC",
    }, undefined, "approval");
    const quiet = new Date("2026-01-01T23:30:00Z");
    strict_1.default.equal((0, policy_1.isQuietHours)(policy, quiet), true);
    strict_1.default.deepEqual((0, policy_1.channelDecision)(policy, quiet), {
        inApp: true, push: false, pushQuietSuppressed: true,
    });
    strict_1.default.deepEqual((0, policy_1.channelDecision)({ ...policy, inAppEnabled: false }, new Date("2026-01-01T12:00:00Z")), {
        inApp: false, push: true, pushQuietSuppressed: false,
    });
});
(0, node_test_1.default)("effective permissions include role/default/overrides and denials win", () => {
    const member = (0, permissions_1.effectiveMembership)({
        userId: "manager",
        member: { status: "active", roleId: "custom", permissions: ["view_notifications"], permissionOverrides: ["approve_sensitive_actions", "view_branch"], permissionDenials: ["approve_sensitive_actions"], assignedBranchIds: ["b1"] },
    });
    strict_1.default.equal((0, permissions_1.hasPermission)(member, "view_notifications"), true);
    strict_1.default.equal((0, permissions_1.hasPermission)(member, "approve_sensitive_actions"), false);
    strict_1.default.equal((0, permissions_1.hasBranchAccess)(member, "b1"), true);
    strict_1.default.equal((0, permissions_1.hasBranchAccess)(member, "b2"), false);
    const owner = (0, permissions_1.effectiveMembership)({ userId: "owner", ownerId: "owner", member: { status: "disabled" } });
    strict_1.default.equal((0, permissions_1.hasPermission)(owner, "anything"), true);
});
(0, node_test_1.default)("SHA-256 IDs are deterministic, scoped, and 64 hex characters", () => {
    const first = (0, ids_1.eventKey)("approval", "biz", "request", "approved");
    strict_1.default.equal(first, (0, ids_1.eventKey)("approval", "biz", "request", "approved"));
    strict_1.default.notEqual(first, (0, ids_1.eventKey)("approval", "biz", "request", "rejected"));
    strict_1.default.match(first, /^[a-f0-9]{64}$/);
    strict_1.default.notEqual((0, ids_1.ledgerId)(first, "u1"), (0, ids_1.notificationId)(first, "u1"));
    strict_1.default.equal((0, ids_1.sha256Id)(" a ", "b"), (0, ids_1.sha256Id)("a", "b"));
});
(0, node_test_1.default)("push payloads flatten safe route parameters for Flutter deep links", () => {
    const payload = (0, delivery_1.payloadData)({
        eventId: "event-1",
        userId: "user-1",
        businessId: "business-1",
        type: "approval_requested",
        category: "approval",
        title: "Approval required",
        body: "Review request",
        routeName: "approvalDetails",
        routeParameters: { approvalId: "approval-1" },
        entityType: "approval_request",
        entityId: "approval-1",
        priority: "high",
    }, "notification-1");
    strict_1.default.equal(payload.routeName, "approvalDetails");
    strict_1.default.equal(payload.approvalId, "approval-1");
    strict_1.default.equal(payload.notificationId, "notification-1");
});
(0, node_test_1.default)("approval recipients require active approval/view/branch permissions and exclude requester", () => {
    const make = (userId, permissions, assigned = ["main"], status = "active") => (0, permissions_1.effectiveMembership)({
        userId, member: { status, roleId: "custom", permissions, assignedBranchIds: assigned },
    });
    const members = [
        make("requester", ["approve_sensitive_actions", "view_approval_notifications", "view_notifications", "view_branch"]),
        make("eligible", ["approve_sensitive_actions", "view_approval_notifications", "view_notifications", "view_branch"]),
        make("denied", ["view_approval_notifications", "view_notifications", "view_branch"]),
        make("wrongBranch", ["approve_sensitive_actions", "view_approval_notifications", "view_notifications", "view_branch"], ["other"]),
        make("disabled", ["approve_sensitive_actions", "view_approval_notifications", "view_notifications", "view_branch"], ["main"], "disabled"),
    ];
    strict_1.default.deepEqual((0, recipients_1.approvalRecipients)({ members, requesterId: "requester", branchId: "main" }), ["eligible"]);
    strict_1.default.deepEqual((0, recipients_1.approvalRecipients)({ members, requesterId: "requester", branchId: "main", assignedApproverIds: ["denied"] }), []);
});
(0, node_test_1.default)("staff observers exclude actor and target and approval-owned activity is ignored", () => {
    const make = (userId) => (0, permissions_1.effectiveMembership)({ userId, member: { status: "active", roleId: "custom", permissions: ["view_staff_activity", "view_staff_notifications", "view_notifications", "view_branch"], assignedBranchIds: ["main"] } });
    strict_1.default.deepEqual((0, recipients_1.staffObserverRecipients)({ members: [make("actor"), make("target"), make("observer")], actorId: "actor", targetId: "target", branchId: "main" }), ["observer"]);
    strict_1.default.equal((0, recipients_1.isApprovalOwnedAction)("approval_requested"), true);
    strict_1.default.equal((0, recipients_1.isApprovalOwnedAction)("sale_created"), false);
});
(0, node_test_1.default)("approval transitions ignore unchanged, cancelled, delete, and invalid direct terminal create", () => {
    strict_1.default.equal((0, approvalTriggers_1.approvalTransition)(undefined, { status: "pending" }), "pending_created");
    strict_1.default.equal((0, approvalTriggers_1.approvalTransition)({ status: "pending" }, { status: "approved" }), "approved");
    strict_1.default.equal((0, approvalTriggers_1.approvalTransition)({ status: "pending" }, { status: "cancelled" }), undefined);
    strict_1.default.equal((0, approvalTriggers_1.approvalTransition)({ status: "pending" }, { status: "pending", updatedAt: 1 }), undefined);
    strict_1.default.equal((0, approvalTriggers_1.approvalTransition)({ status: "approved" }, { status: "rejected" }), undefined);
    strict_1.default.equal((0, approvalTriggers_1.approvalTransition)(undefined, { status: "approved" }), undefined);
    strict_1.default.equal((0, approvalTriggers_1.approvalTransition)({ status: "pending" }, undefined), undefined);
});
//# sourceMappingURL=notifications.test.js.map