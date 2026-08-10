import { FieldValue } from "firebase-admin/firestore";
import { adminFirestore } from "@/lib/firebase/admin";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS } from "@/lib/platform/collections";
import { writeAdminActivity } from "@/lib/platform-admin/repository";

export type AdminBusinessRow = {
  id: string;
  name: string;
  ownerId: string;
  businessType: string | null;
  status: string;
  email: string | null;
  phoneNumber: string | null;
  district: string | null;
  country: string | null;
  currency: string | null;
  isDemo: boolean;
  createdAt: Date | null;
  updatedAt: Date | null;
  memberCount: number;
};

export async function listBusinesses(limit = 100): Promise<AdminBusinessRow[]> {
  const snap = await adminFirestore()
    .collection(COLLECTIONS.businesses)
    .orderBy("name")
    .limit(limit)
    .get()
    .catch(async () =>
      adminFirestore().collection(COLLECTIONS.businesses).limit(limit).get(),
    );

  const rows = await Promise.all(
    snap.docs.map(async (doc) => {
      const data = doc.data() ?? {};
      let memberCount = 0;
      try {
        const members = await doc.ref.collection("members").count().get();
        memberCount = members.data().count;
      } catch {
        const members = await doc.ref.collection("members").limit(50).get();
        memberCount = members.size;
      }
      return {
        id: doc.id,
        name: typeof data.name === "string" ? data.name : doc.id,
        ownerId: typeof data.ownerId === "string" ? data.ownerId : "",
        businessType:
          typeof data.businessType === "string" ? data.businessType : null,
        status: typeof data.status === "string" ? data.status : "active",
        email: typeof data.email === "string" ? data.email : null,
        phoneNumber:
          typeof data.phoneNumber === "string" ? data.phoneNumber : null,
        district: typeof data.district === "string" ? data.district : null,
        country: typeof data.country === "string" ? data.country : null,
        currency: typeof data.currency === "string" ? data.currency : null,
        isDemo: data.isDemo === true,
        createdAt: asDate(data.createdAt),
        updatedAt: asDate(data.updatedAt),
        memberCount,
      } satisfies AdminBusinessRow;
    }),
  );

  return rows;
}

export async function getBusiness(
  businessId: string,
): Promise<AdminBusinessRow | null> {
  const doc = await adminFirestore()
    .collection(COLLECTIONS.businesses)
    .doc(businessId)
    .get();
  if (!doc.exists) return null;
  const data = doc.data() ?? {};
  let memberCount = 0;
  try {
    const members = await doc.ref.collection("members").count().get();
    memberCount = members.data().count;
  } catch {
    const members = await doc.ref.collection("members").limit(50).get();
    memberCount = members.size;
  }
  return {
    id: doc.id,
    name: typeof data.name === "string" ? data.name : doc.id,
    ownerId: typeof data.ownerId === "string" ? data.ownerId : "",
    businessType:
      typeof data.businessType === "string" ? data.businessType : null,
    status: typeof data.status === "string" ? data.status : "active",
    email: typeof data.email === "string" ? data.email : null,
    phoneNumber:
      typeof data.phoneNumber === "string" ? data.phoneNumber : null,
    district: typeof data.district === "string" ? data.district : null,
    country: typeof data.country === "string" ? data.country : null,
    currency: typeof data.currency === "string" ? data.currency : null,
    isDemo: data.isDemo === true,
    createdAt: asDate(data.createdAt),
    updatedAt: asDate(data.updatedAt),
    memberCount,
  };
}

export async function setBusinessStatus(input: {
  businessId: string;
  status: "active" | "archived";
  actorUid: string;
  actorName: string | null;
  actorRole: string;
  reason?: string | null;
}): Promise<void> {
  await adminFirestore()
    .collection(COLLECTIONS.businesses)
    .doc(input.businessId)
    .set(
      {
        status: input.status,
        statusUpdatedAt: FieldValue.serverTimestamp(),
        statusUpdatedBy: input.actorUid,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType:
      input.status === "archived" ? "archive_business" : "restore_business",
    targetType: "business",
    targetId: input.businessId,
    description: `${input.status === "archived" ? "Archived" : "Restored"} business ${input.businessId}`,
    reason: input.reason ?? null,
  });
}
