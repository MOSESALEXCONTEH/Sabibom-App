import {createHash} from "crypto";
import {FieldValue} from "firebase-admin/firestore";
import {adminFirestore} from "../config/firebase-admin";

function normalizeQuestion(question: string): string {
  return question
    .toLowerCase()
    .replace(/[^\w\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function unansweredDocId(businessId: string, normalized: string): string {
  return createHash("sha1")
    .update(`${businessId}::${normalized}`)
    .digest("hex")
    .slice(0, 24);
}

/** Persists asks Sabi could not answer from verified records (training inbox). */
export async function recordUnansweredSabiAsk(input: {
  businessId: string;
  userId: string;
  question: string;
  reply?: string | null;
  replyLanguage?: string | null;
  source?: string;
}): Promise<void> {
  const question = input.question.trim();
  if (!input.businessId || question.length < 3) return;
  const normalized = normalizeQuestion(question);
  if (!normalized) return;
  const id = unansweredDocId(input.businessId, normalized);
  const db = adminFirestore();
  const payload = {
    id,
    businessId: input.businessId,
    userId: input.userId,
    question,
    questionNormalized: normalized,
    reply: input.reply?.trim() || null,
    replyLanguage: input.replyLanguage ?? null,
    source: input.source ?? "business_question_unknown",
    status: "new",
    count: FieldValue.increment(1),
    lastAskedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  const globalRef = db.collection("sabi_unanswered").doc(id);
  const businessRef = db
    .collection("businesses")
    .doc(input.businessId)
    .collection("sabi_unanswered")
    .doc(id);

  const [globalSnap, businessSnap] = await Promise.all([
    globalRef.get(),
    businessRef.get(),
  ]);

  await Promise.all([
    globalRef.set(
      {
        ...payload,
        ...(globalSnap.exists
          ? {}
          : {createdAt: FieldValue.serverTimestamp()}),
      },
      {merge: true},
    ),
    businessRef.set(
      {
        ...payload,
        ...(businessSnap.exists
          ? {}
          : {createdAt: FieldValue.serverTimestamp()}),
      },
      {merge: true},
    ),
  ]);
}
