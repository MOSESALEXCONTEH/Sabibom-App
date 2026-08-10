/**
 * One-time Super Admin bootstrap.
 *
 * Looks up an existing Firebase Auth user by email and creates
 * platform_admins/{uid} with role super_admin.
 *
 * Never creates Firebase passwords or Auth users.
 *
 * Usage:
 *   BOOTSTRAP_ALLOW=true BOOTSTRAP_SUPER_ADMIN_EMAIL=you@example.com \
 *     npm run bootstrap:super-admin
 *
 * After success: unset BOOTSTRAP_ALLOW and BOOTSTRAP_SUPER_ADMIN_EMAIL.
 */
import { FieldValue } from "firebase-admin/firestore";
import { adminAuth, adminFirestore } from "../src/lib/firebase/admin";
import {
  PLATFORM_ADMINS_COLLECTION,
  PLATFORM_ADMIN_ACTIVITY_COLLECTION,
} from "../src/lib/platform-admin/repository";
import {
  PLATFORM_PERMISSIONS,
  permissionsForRole,
} from "../src/lib/permissions/registry";

export type BootstrapResult =
  | { status: "created"; uid: string }
  | { status: "already_active_super_admin"; uid: string }
  | { status: "refused_overwrite"; uid: string; reason: string }
  | { status: "forced_upgrade"; uid: string };

export function readBootstrapConfig(env: NodeJS.ProcessEnv = process.env): {
  email: string;
  allow: boolean;
  force: boolean;
} {
  const allow = env.BOOTSTRAP_ALLOW === "true";
  const force = env.BOOTSTRAP_FORCE === "true";
  const email = (env.BOOTSTRAP_SUPER_ADMIN_EMAIL || "").trim().toLowerCase();
  return { email, allow, force };
}

export async function bootstrapSuperAdmin(deps: {
  getUserByEmail: (email: string) => Promise<{
    uid: string;
    email?: string;
    displayName?: string;
    photoURL?: string;
  }>;
  getAdminDoc: (uid: string) => Promise<Record<string, unknown> | null>;
  setAdminDoc: (uid: string, data: Record<string, unknown>) => Promise<void>;
  writeActivity: (data: Record<string, unknown>) => Promise<void>;
  serverTimestamp: () => unknown;
  config: { email: string; allow: boolean; force: boolean };
  /** Test seam — must never be used to create Auth users in production path. */
  createUser?: never;
}): Promise<BootstrapResult> {
  if (!deps.config.allow) {
    throw new Error(
      "Bootstrap refused: set BOOTSTRAP_ALLOW=true to run this one-time script.",
    );
  }
  if (!deps.config.email || !deps.config.email.includes("@")) {
    throw new Error(
      "Bootstrap refused: BOOTSTRAP_SUPER_ADMIN_EMAIL must be a valid email.",
    );
  }

  const user = await deps.getUserByEmail(deps.config.email);
  const existing = await deps.getAdminDoc(user.uid);

  if (existing) {
    const role = existing.role;
    const status = existing.status;
    if (role === "super_admin" && status === "active") {
      return { status: "already_active_super_admin", uid: user.uid };
    }
    if (!deps.config.force) {
      return {
        status: "refused_overwrite",
        uid: user.uid,
        reason: `Existing platform_admins doc has role=${String(role)} status=${String(status)}. Set BOOTSTRAP_FORCE=true only if you intentionally need to upgrade.`,
      };
    }
    await deps.setAdminDoc(user.uid, {
      uid: user.uid,
      displayName: user.displayName || existing.displayName || null,
      email: user.email || deps.config.email,
      photoUrl: user.photoURL || existing.photoUrl || null,
      role: "super_admin",
      permissions: [...PLATFORM_PERMISSIONS],
      status: "active",
      mfaRequired: existing.mfaRequired === true,
      updatedBy: "bootstrap_script",
      updatedAt: deps.serverTimestamp(),
      notes:
        typeof existing.notes === "string"
          ? existing.notes
          : "Upgraded by bootstrap script",
    });
    await deps.writeActivity({
      adminUid: "bootstrap_script",
      adminName: "bootstrap_script",
      adminRole: "bootstrap_script",
      actionType: "admin_bootstrapped",
      targetType: "platform_admin",
      targetId: user.uid,
      targetLabel: null,
      description: "Forced bootstrap upgrade to active super_admin",
      reason: "BOOTSTRAP_FORCE=true",
      metadata: { previousRole: role, previousStatus: status },
      requestId: null,
      createdAt: deps.serverTimestamp(),
    });
    return { status: "forced_upgrade", uid: user.uid };
  }

  const permissions = permissionsForRole("super_admin");
  await deps.setAdminDoc(user.uid, {
    uid: user.uid,
    displayName: user.displayName || null,
    email: user.email || deps.config.email,
    photoUrl: user.photoURL || null,
    role: "super_admin",
    permissions,
    status: "active",
    createdBy: "bootstrap_script",
    createdAt: deps.serverTimestamp(),
    updatedBy: "bootstrap_script",
    updatedAt: deps.serverTimestamp(),
    lastLoginAt: null,
    lastActiveAt: null,
    mfaRequired: false,
    notes: "Created by one-time bootstrap script",
  });

  await deps.writeActivity({
    adminUid: "bootstrap_script",
    adminName: "bootstrap_script",
    adminRole: "bootstrap_script",
    actionType: "admin_created",
    targetType: "platform_admin",
    targetId: user.uid,
    targetLabel: null,
    description:
      "Bootstrapped first super_admin from existing Firebase Auth user",
    reason: null,
    metadata: null,
    requestId: null,
    createdAt: deps.serverTimestamp(),
  });

  return { status: "created", uid: user.uid };
}

async function main() {
  const config = readBootstrapConfig();
  const auth = adminAuth();
  const db = adminFirestore();

  const result = await bootstrapSuperAdmin({
    config,
    serverTimestamp: () => FieldValue.serverTimestamp(),
    getUserByEmail: async (email) => {
      const record = await auth.getUserByEmail(email);
      return {
        uid: record.uid,
        email: record.email,
        displayName: record.displayName,
        photoURL: record.photoURL,
      };
    },
    getAdminDoc: async (uid) => {
      const snap = await db.collection(PLATFORM_ADMINS_COLLECTION).doc(uid).get();
      return snap.exists ? (snap.data() as Record<string, unknown>) : null;
    },
    setAdminDoc: async (uid, data) => {
      await db
        .collection(PLATFORM_ADMINS_COLLECTION)
        .doc(uid)
        .set(data, { merge: true });
    },
    writeActivity: async (data) => {
      const ref = db.collection(PLATFORM_ADMIN_ACTIVITY_COLLECTION).doc();
      await ref.set({ ...data, id: ref.id });
    },
  });

  if (result.status === "refused_overwrite") {
    console.error(`BOOTSTRAP_REFUSED uid=${result.uid}`);
    console.error(result.reason);
    process.exitCode = 2;
    return;
  }

  console.log(`BOOTSTRAP_OK status=${result.status} uid=${result.uid}`);
  console.log(
    "Disable bootstrap: unset BOOTSTRAP_ALLOW and BOOTSTRAP_SUPER_ADMIN_EMAIL.",
  );
}

const invokedDirectly = process.argv[1]?.includes("bootstrap-super-admin");
if (invokedDirectly) {
  main().catch((error) => {
    console.error(
      "BOOTSTRAP_FAILED",
      error instanceof Error ? error.message : "unknown_error",
    );
    process.exitCode = 1;
  });
}
