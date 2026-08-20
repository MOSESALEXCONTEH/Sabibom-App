import assert from "node:assert/strict";
import test from "node:test";
import {approvalTransition} from "./approvalTriggers";
import {payloadData} from "./delivery";
import {eventKey, ledgerId, notificationId, sha256Id} from "./ids";
import {
  effectiveMembership,
  hasBranchAccess,
  hasPermission,
} from "./permissions";
import {
  channelDecision,
  isQuietHours,
  resolveNotificationPolicy,
} from "./policy";
import {
  approvalRecipients,
  isApprovalOwnedAction,
  staffObserverRecipients,
} from "./recipients";

test("business preferences win, legacy is fallback, defaults allow", () => {
  const business = resolveNotificationPolicy(
    {approvalEnabled: false, inAppEnabled: true},
    {approvalEnabled: true, pushEnabled: false},
    "approval",
  );
  assert.equal(business.categoryEnabled, false);
  assert.equal(business.pushEnabled, true);
  const legacy = resolveNotificationPolicy(undefined, {team: false}, "staffActivity");
  assert.equal(legacy.categoryEnabled, false);
  const defaults = resolveNotificationPolicy(undefined, undefined, "approval");
  assert.deepEqual([defaults.inAppEnabled, defaults.pushEnabled, defaults.categoryEnabled], [true, true, true]);
});

test("in-app and push are independent and quiet hours suppress push only", () => {
  const policy = resolveNotificationPolicy({
    inAppEnabled: true, pushEnabled: true, approvalEnabled: true,
    quietHoursEnabled: true, quietHoursStart: "22:00", quietHoursEnd: "07:00",
    timezone: "UTC",
  }, undefined, "approval");
  const quiet = new Date("2026-01-01T23:30:00Z");
  assert.equal(isQuietHours(policy, quiet), true);
  assert.deepEqual(channelDecision(policy, quiet), {
    inApp: true, push: false, pushQuietSuppressed: true,
  });
  assert.deepEqual(channelDecision({...policy, inAppEnabled: false}, new Date("2026-01-01T12:00:00Z")), {
    inApp: false, push: true, pushQuietSuppressed: false,
  });
});

test("effective permissions include role/default/overrides and denials win", () => {
  const member = effectiveMembership({
    userId: "manager",
    member: {status: "active", roleId: "custom", permissions: ["view_notifications"], permissionOverrides: ["approve_sensitive_actions", "view_branch"], permissionDenials: ["approve_sensitive_actions"], assignedBranchIds: ["b1"]},
  });
  assert.equal(hasPermission(member, "view_notifications"), true);
  assert.equal(hasPermission(member, "approve_sensitive_actions"), false);
  assert.equal(hasBranchAccess(member, "b1"), true);
  assert.equal(hasBranchAccess(member, "b2"), false);
  const owner = effectiveMembership({userId: "owner", ownerId: "owner", member: {status: "disabled"}});
  assert.equal(hasPermission(owner, "anything"), true);
});

test("SHA-256 IDs are deterministic, scoped, and 64 hex characters", () => {
  const first = eventKey("approval", "biz", "request", "approved");
  assert.equal(first, eventKey("approval", "biz", "request", "approved"));
  assert.notEqual(first, eventKey("approval", "biz", "request", "rejected"));
  assert.match(first, /^[a-f0-9]{64}$/);
  assert.notEqual(ledgerId(first, "u1"), notificationId(first, "u1"));
  assert.equal(sha256Id(" a ", "b"), sha256Id("a", "b"));
});

test("push payloads flatten safe route parameters for Flutter deep links", () => {
  const payload = payloadData({
    eventId: "event-1",
    userId: "user-1",
    businessId: "business-1",
    type: "approval_requested",
    category: "approval",
    title: "Approval required",
    body: "Review request",
    routeName: "approvalDetails",
    routeParameters: {approvalId: "approval-1"},
    entityType: "approval_request",
    entityId: "approval-1",
    priority: "high",
  }, "notification-1");
  assert.equal(payload.routeName, "approvalDetails");
  assert.equal(payload.approvalId, "approval-1");
  assert.equal(payload.notificationId, "notification-1");
});

test("approval recipients require active approval/view/branch permissions and exclude requester", () => {
  const make = (userId: string, permissions: string[], assigned = ["main"], status = "active") => effectiveMembership({
    userId, member: {status, roleId: "custom", permissions, assignedBranchIds: assigned},
  });
  const members = [
    make("requester", ["approve_sensitive_actions", "view_approval_notifications", "view_notifications", "view_branch"]),
    make("eligible", ["approve_sensitive_actions", "view_approval_notifications", "view_notifications", "view_branch"]),
    make("denied", ["view_approval_notifications", "view_notifications", "view_branch"]),
    make("wrongBranch", ["approve_sensitive_actions", "view_approval_notifications", "view_notifications", "view_branch"], ["other"]),
    make("disabled", ["approve_sensitive_actions", "view_approval_notifications", "view_notifications", "view_branch"], ["main"], "disabled"),
  ];
  assert.deepEqual(approvalRecipients({members, requesterId: "requester", branchId: "main"}), ["eligible"]);
  assert.deepEqual(approvalRecipients({members, requesterId: "requester", branchId: "main", assignedApproverIds: ["denied"]}), []);
});

test("staff observers exclude actor and target and approval-owned activity is ignored", () => {
  const make = (userId: string) => effectiveMembership({userId, member: {status: "active", roleId: "custom", permissions: ["view_staff_activity", "view_staff_notifications", "view_notifications", "view_branch"], assignedBranchIds: ["main"]}});
  assert.deepEqual(staffObserverRecipients({members: [make("actor"), make("target"), make("observer")], actorId: "actor", targetId: "target", branchId: "main"}), ["observer"]);
  assert.equal(isApprovalOwnedAction("approval_requested"), true);
  assert.equal(isApprovalOwnedAction("sale_created"), false);
});

test("approval transitions ignore unchanged, cancelled, delete, and invalid direct terminal create", () => {
  assert.equal(approvalTransition(undefined, {status: "pending"}), "pending_created");
  assert.equal(approvalTransition({status: "pending"}, {status: "approved"}), "approved");
  assert.equal(approvalTransition({status: "pending"}, {status: "cancelled"}), undefined);
  assert.equal(approvalTransition({status: "pending"}, {status: "pending", updatedAt: 1}), undefined);
  assert.equal(approvalTransition({status: "approved"}, {status: "rejected"}), undefined);
  assert.equal(approvalTransition(undefined, {status: "approved"}), undefined);
  assert.equal(approvalTransition({status: "pending"}, undefined), undefined);
});
