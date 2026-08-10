#!/usr/bin/env node
/* eslint-disable no-console */

/**
 * Idempotent branch-access migration. Dry-run is the default.
 *
 * Preview:
 *   node scripts/migrate-branch-access.cjs
 * Apply only after review and backup:
 *   node scripts/migrate-branch-access.cjs --apply
 */
const {applicationDefault, cert, getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

const APPLY = process.argv.includes("--apply");
const aliases = new Map([
  ["view_branches", "view_branch"],
  ["switch_branches", "switch_branch"],
  ["view_all_branch_reports", "view_combined_reports"],
  ["manage_branch_staff", "assign_staff_to_branches"],
]);

function credential() {
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL?.trim();
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, "\n");
  return projectId && clientEmail && privateKey
    ? cert({projectId, clientEmail, privateKey})
    : applicationDefault();
}

if (getApps().length === 0) initializeApp({credential: credential()});
const db = getFirestore();
const counts = {
  businesses: 0,
  members: 0,
  changed: 0,
  assignmentsRemoved: 0,
  mainAssignmentsAdded: 0,
};

function strings(value) {
  return Array.isArray(value)
    ? [...new Set(value.filter((item) => typeof item === "string").map((item) => item.trim()).filter(Boolean))]
    : [];
}

async function run() {
  const businesses = await db.collection("businesses").get();
  for (const business of businesses.docs) {
    counts.businesses += 1;
    const branches = await business.ref.collection("branches").get();
    const activeIds = new Set(
      branches.docs
        .filter((branch) => branch.data().status === "active")
        .map((branch) => branch.id),
    );
    const hasMain = activeIds.has("main");
    const members = await business.ref.collection("members").get();

    for (const member of members.docs) {
      counts.members += 1;
      const data = member.data();
      const role = String(data.roleId || data.role || "cashier");
      const isOwner =
        data.isOwner === true ||
        role === "owner" ||
        business.data().ownerId === member.id;
      const previousAssignments = strings(data.assignedBranchIds);
      let assignments = previousAssignments.filter((id) => activeIds.has(id));
      counts.assignmentsRemoved += previousAssignments.length - assignments.length;

      // Legacy empty assignments represented Main Branch for non-owners.
      if (!isOwner && assignments.length === 0 && hasMain) {
        assignments = ["main"];
        counts.mainAssignmentsAdded += 1;
      }

      const permissions = strings(data.permissions).map(
        (permission) => aliases.get(permission) || permission,
      );
      const overrides = strings(data.permissionOverrides).map(
        (permission) => aliases.get(permission) || permission,
      );
      const denials = new Set(
        strings(data.permissionDenials).map(
          (permission) => aliases.get(permission) || permission,
        ),
      );
      const effective = new Set([...permissions, ...overrides]);
      if (!isOwner && !denials.has("view_branch")) effective.add("view_branch");
      if (
        !isOwner &&
        ["admin", "manager"].includes(role) &&
        assignments.length > 1 &&
        !denials.has("switch_branch")
      ) {
        effective.add("switch_branch");
      }
      // Staff and cashiers are deliberately not granted switch_branch.
      const defaultBranchId = assignments.includes(String(data.defaultBranchId))
        ? data.defaultBranchId
        : assignments[0] || null;
      const next = {
        assignedBranchIds: assignments,
        defaultBranchId,
        permissions: [...effective],
        permissionOverrides: [...new Set(overrides)],
        permissionDenials: [...denials],
        branchAccessSchemaVersion: 2,
      };
      const changed = JSON.stringify({
        assignedBranchIds: previousAssignments,
        defaultBranchId: data.defaultBranchId || null,
        permissions: strings(data.permissions),
        permissionOverrides: strings(data.permissionOverrides),
        permissionDenials: strings(data.permissionDenials),
        branchAccessSchemaVersion: data.branchAccessSchemaVersion,
      }) !== JSON.stringify(next);
      if (!changed) continue;
      counts.changed += 1;
      if (APPLY) {
        await member.ref.set(
          {...next, updatedAt: FieldValue.serverTimestamp()},
          {merge: true},
        );
      }
    }
  }
  console.log(JSON.stringify({mode: APPLY ? "apply" : "dry-run", ...counts}, null, 2));
}

run().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
