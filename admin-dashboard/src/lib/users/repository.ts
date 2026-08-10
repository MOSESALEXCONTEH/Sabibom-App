import { FieldValue } from "firebase-admin/firestore";
import { adminAuth, adminFirestore } from "@/lib/firebase/admin";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS } from "@/lib/platform/collections";
import { writeAdminActivity } from "@/lib/platform-admin/repository";

export type AdminUserRow = {
  uid: string;
  email: string | null;
  displayName: string | null;
  fullName: string | null;
  phoneNumber: string | null;
  disabled: boolean;
  platformStatus: string;
  businessSetupStatus: string | null;
  activeBusinessId: string | null;
  businessName: string | null;
  createdAt: Date | null;
  lastSignInAt: Date | null;
};

export async function listUsers(limit = 100): Promise<AdminUserRow[]> {
  const [authList, profileSnap] = await Promise.all([
    adminAuth().listUsers(Math.min(limit, 1000)),
    adminFirestore().collection(COLLECTIONS.users).limit(limit).get(),
  ]);

  const profiles = new Map(
    profileSnap.docs.map((doc) => [doc.id, doc.data() ?? {}]),
  );

  return authList.users.map((user) => {
    const profile = profiles.get(user.uid) ?? {};
    return {
      uid: user.uid,
      email: user.email ?? null,
      displayName: user.displayName ?? null,
      fullName:
        typeof profile.fullName === "string" ? profile.fullName : null,
      phoneNumber: user.phoneNumber ?? null,
      disabled: user.disabled,
      platformStatus:
        typeof profile.platformStatus === "string"
          ? profile.platformStatus
          : user.disabled
            ? "disabled"
            : "active",
      businessSetupStatus:
        typeof profile.businessSetupStatus === "string"
          ? profile.businessSetupStatus
          : null,
      activeBusinessId:
        typeof profile.activeBusinessId === "string"
          ? profile.activeBusinessId
          : null,
      businessName:
        typeof profile.businessName === "string"
          ? profile.businessName
          : null,
      createdAt: user.metadata.creationTime
        ? new Date(user.metadata.creationTime)
        : null,
      lastSignInAt: user.metadata.lastSignInTime
        ? new Date(user.metadata.lastSignInTime)
        : asDate(profile.lastLoginAt),
    };
  });
}

export async function getUser(uid: string): Promise<AdminUserRow | null> {
  try {
    const [authUser, profileSnap] = await Promise.all([
      adminAuth().getUser(uid),
      adminFirestore().collection(COLLECTIONS.users).doc(uid).get(),
    ]);
    const profile = profileSnap.data() ?? {};
    return {
      uid: authUser.uid,
      email: authUser.email ?? null,
      displayName: authUser.displayName ?? null,
      fullName:
        typeof profile.fullName === "string" ? profile.fullName : null,
      phoneNumber: authUser.phoneNumber ?? null,
      disabled: authUser.disabled,
      platformStatus:
        typeof profile.platformStatus === "string"
          ? profile.platformStatus
          : authUser.disabled
            ? "disabled"
            : "active",
      businessSetupStatus:
        typeof profile.businessSetupStatus === "string"
          ? profile.businessSetupStatus
          : null,
      activeBusinessId:
        typeof profile.activeBusinessId === "string"
          ? profile.activeBusinessId
          : null,
      businessName:
        typeof profile.businessName === "string"
          ? profile.businessName
          : null,
      createdAt: authUser.metadata.creationTime
        ? new Date(authUser.metadata.creationTime)
        : null,
      lastSignInAt: authUser.metadata.lastSignInTime
        ? new Date(authUser.metadata.lastSignInTime)
        : null,
    };
  } catch {
    return null;
  }
}

export async function setUserDisabled(input: {
  uid: string;
  disabled: boolean;
  actorUid: string;
  actorName: string | null;
  actorRole: string;
  reason?: string | null;
}): Promise<void> {
  await adminAuth().updateUser(input.uid, { disabled: input.disabled });
  await adminFirestore()
    .collection(COLLECTIONS.users)
    .doc(input.uid)
    .set(
      {
        platformStatus: input.disabled ? "disabled" : "active",
        platformStatusUpdatedAt: FieldValue.serverTimestamp(),
        platformStatusUpdatedBy: input.actorUid,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType: input.disabled ? "disable_user" : "restore_user",
    targetType: "user",
    targetId: input.uid,
    description: input.disabled
      ? `Disabled user ${input.uid}`
      : `Restored user ${input.uid}`,
    reason: input.reason ?? null,
  });
}
