import {getFirestore} from "firebase-admin/firestore";
import {
  permissionDenied,
  unauthenticated,
} from "../shared/errors";

export async function requireAuthenticatedUid(
  authUid: string | undefined,
): Promise<string> {
  if (!authUid) {
    throw unauthenticated();
  }
  return authUid;
}

/**
 * Verifies the caller owns or is an active member of the business.
 * Never trust client-supplied businessId alone.
 */
export async function requireBusinessMember(
  uid: string,
  businessId: string,
): Promise<{role: string; isOwner: boolean}> {
  const trimmed = businessId.trim();
  if (!trimmed) {
    throw permissionDenied();
  }

  const db = getFirestore();
  const businessSnap = await db.collection("businesses").doc(trimmed).get();
  if (!businessSnap.exists) {
    throw permissionDenied();
  }

  const ownerId = businessSnap.data()?.ownerId as string | undefined;
  if (ownerId === uid) {
    return {role: "owner", isOwner: true};
  }

  const memberSnap = await db
    .collection("businesses")
    .doc(trimmed)
    .collection("members")
    .doc(uid)
    .get();

  if (!memberSnap.exists) {
    throw permissionDenied();
  }

  const member = memberSnap.data() ?? {};
  if (member.status !== "active") {
    throw permissionDenied();
  }

  const role = (member.role as string | undefined) ?? "cashier";
  return {role, isOwner: false};
}

export function requireOwnerOrManager(role: string, isOwner: boolean): void {
  if (isOwner) return;
  if (role === "owner" || role === "manager") return;
  throw permissionDenied();
}
