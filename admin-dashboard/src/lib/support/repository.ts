import { FieldValue } from "firebase-admin/firestore";
import { adminFirestore } from "@/lib/firebase/admin";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS } from "@/lib/platform/collections";
import { writeAdminActivity } from "@/lib/platform-admin/repository";

export type FeedbackRow = {
  id: string;
  userId: string;
  title: string;
  description: string;
  category: string;
  status: string;
  priority: string;
  businessId: string | null;
  appVersion: string | null;
  platform: string | null;
  createdAt: Date | null;
  updatedAt: Date | null;
};

function mapFeedback(
  id: string,
  data: FirebaseFirestore.DocumentData,
): FeedbackRow {
  return {
    id,
    userId: typeof data.userId === "string" ? data.userId : "",
    title: typeof data.title === "string" ? data.title : "(untitled)",
    description:
      typeof data.description === "string" ? data.description : "",
    category: typeof data.category === "string" ? data.category : "other",
    status: typeof data.status === "string" ? data.status : "new",
    priority: typeof data.priority === "string" ? data.priority : "normal",
    businessId: typeof data.businessId === "string" ? data.businessId : null,
    appVersion: typeof data.appVersion === "string" ? data.appVersion : null,
    platform: typeof data.platform === "string" ? data.platform : null,
    createdAt: asDate(data.createdAt),
    updatedAt: asDate(data.updatedAt),
  };
}

export async function listFeedback(limit = 100): Promise<FeedbackRow[]> {
  const snap = await adminFirestore()
    .collection(COLLECTIONS.feedback)
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get()
    .catch(async () =>
      adminFirestore().collection(COLLECTIONS.feedback).limit(limit).get(),
    );
  return snap.docs.map((doc) => mapFeedback(doc.id, doc.data() ?? {}));
}

export async function updateFeedbackStatus(input: {
  id: string;
  status: string;
  actorUid: string;
  actorName: string | null;
  actorRole: string;
}): Promise<void> {
  await adminFirestore()
    .collection(COLLECTIONS.feedback)
    .doc(input.id)
    .set(
      {
        status: input.status,
        updatedAt: FieldValue.serverTimestamp(),
        reviewedBy: input.actorUid,
      },
      { merge: true },
    );
  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType: "update_feedback_status",
    targetType: "feedback",
    targetId: input.id,
    description: `Set feedback ${input.id} to ${input.status}`,
  });
}

export type SabiUnansweredRow = {
  id: string;
  businessId: string;
  userId: string | null;
  question: string;
  reply: string | null;
  source: string | null;
  status: string;
  count: number;
  createdAt: Date | null;
  lastAskedAt: Date | null;
};

export async function listSabiUnanswered(
  limit = 100,
): Promise<SabiUnansweredRow[]> {
  const snap = await adminFirestore()
    .collection(COLLECTIONS.sabiUnanswered)
    .orderBy("lastAskedAt", "desc")
    .limit(limit)
    .get()
    .catch(async () =>
      adminFirestore()
        .collection(COLLECTIONS.sabiUnanswered)
        .limit(limit)
        .get(),
    );
  return snap.docs.map((doc) => {
    const data = doc.data() ?? {};
    return {
      id: doc.id,
      businessId: typeof data.businessId === "string" ? data.businessId : "",
      userId: typeof data.userId === "string" ? data.userId : null,
      question: typeof data.question === "string" ? data.question : "",
      reply: typeof data.reply === "string" ? data.reply : null,
      source: typeof data.source === "string" ? data.source : null,
      status: typeof data.status === "string" ? data.status : "new",
      count: typeof data.count === "number" ? data.count : 1,
      createdAt: asDate(data.createdAt),
      lastAskedAt: asDate(data.lastAskedAt),
    };
  });
}

export async function updateSabiUnansweredStatus(input: {
  id: string;
  status: string;
  actorUid: string;
  actorName: string | null;
  actorRole: string;
}): Promise<void> {
  await adminFirestore()
    .collection(COLLECTIONS.sabiUnanswered)
    .doc(input.id)
    .set(
      {
        status: input.status,
        reviewedAt: FieldValue.serverTimestamp(),
        reviewedBy: input.actorUid,
      },
      { merge: true },
    );
  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType: "update_sabi_unanswered",
    targetType: "sabi_unanswered",
    targetId: input.id,
    description: `Marked Sabi unanswered ${input.id} as ${input.status}`,
  });
}
