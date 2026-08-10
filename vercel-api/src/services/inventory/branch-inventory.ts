import type {
  DocumentData,
  DocumentReference,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import { resolveBranchAuthorization } from "../team/branch-access.js";
import {errors} from "../../utils/api-errors";

export interface ActiveBranchContext {
  businessRef: DocumentReference<DocumentData>;
  branchRef: DocumentReference<DocumentData>;
  branchId: string;
  branchName: string;
  branchCode: string;
}

/**
 * Validates a real writable branch and the authenticated user's assignment.
 * The special All Branches view is never accepted as a write target.
 */
export async function requireActiveBranchAccess(input: {
  db: Firestore;
  uid: string;
  businessId: string;
  branchId: string;
}): Promise<ActiveBranchContext> {
  const branchId = normalizeWritableBranchId(input.branchId);
  const businessRef = input.db.collection("businesses").doc(input.businessId);
  const branchRef = businessRef.collection("branches").doc(branchId);
  const memberRef = businessRef.collection("members").doc(input.uid);
  const [businessSnapshot, branchSnapshot, memberSnapshot] = await Promise.all([
    businessRef.get(),
    branchRef.get(),
    memberRef.get(),
  ]);

  if (!businessSnapshot.exists) {
    throw errors.notFound("The selected business no longer exists.");
  }
  if (!branchSnapshot.exists) {
    throw errors.invalidArgument("The selected branch no longer exists.");
  }
  const branchData = branchSnapshot.data() ?? {};
  if (
    branchData.businessId !== input.businessId ||
    branchData.status !== "active"
  ) {
    throw errors.invalidArgument(
      "Switch to an active branch before changing inventory.",
    );
  }

  const businessData = businessSnapshot.data() ?? {};
  const memberData = memberSnapshot.data() ?? {};
  const access = resolveBranchAuthorization({
    uid: input.uid,
    ownerId: businessData.ownerId,
    memberExists: memberSnapshot.exists,
    memberData,
  });
  if (!access.canAccessBranch(branchId)) {
    throw errors.invalidArgument("You do not have access to this branch.");
  }

  return {
    businessRef,
    branchRef,
    branchId,
    branchName: safeText(branchData.name, "Branch"),
    branchCode: safeText(branchData.code, branchId).toUpperCase(),
  };
}

/** Re-checks branch state inside the mutation transaction. */
export async function assertActiveBranchInTransaction(input: {
  transaction: Transaction;
  branchRef: DocumentReference<DocumentData>;
  businessId: string;
}): Promise<void> {
  const snapshot = await input.transaction.get(input.branchRef);
  const data = snapshot.data() ?? {};
  if (
    !snapshot.exists ||
    data.businessId !== input.businessId ||
    data.status !== "active"
  ) {
    throw errors.invalidArgument(
      "This branch is inactive and cannot accept inventory changes.",
    );
  }
}

export function branchInventoryRef(
  context: Pick<ActiveBranchContext, "branchRef">,
  productId: string,
): DocumentReference<DocumentData> {
  return context.branchRef.collection("inventory").doc(productId);
}

export function normalizeWritableBranchId(value: string): string {
  const branchId = value.trim();
  if (
    branchId.length === 0 ||
    branchId.toLowerCase() === "all" ||
    branchId.toLowerCase() === "all_branches"
  ) {
    throw errors.invalidArgument(
      "Switch to a single active branch before changing inventory.",
    );
  }
  if (branchId.length > 128 || branchId.includes("/")) {
    throw errors.invalidArgument("The selected branch is invalid.");
  }
  return branchId;
}

export function requireBranchIdInBody(body: unknown): void {
  const branchId =
    typeof body === "object" &&
    body !== null &&
    typeof (body as Record<string, unknown>).branchId === "string"
      ? (body as Record<string, string>).branchId.trim()
      : "";
  if (!branchId) {
    throw errors.branchRequired();
  }
}

export function inventoryNumber(
  data: Record<string, unknown> | undefined,
  field: string,
  fallback = 0,
): number {
  const value = data?.[field];
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : fallback;
}

function safeText(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : fallback;
}
