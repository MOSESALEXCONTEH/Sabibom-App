import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {adminFirestore} from "../config/firebase-admin";
import {errors} from "../utils/api-errors";

export type SabiTrainingExample = {
  id: string;
  utterance: string;
  intent: string;
  clarification: string | null;
  suggestedPrompt: string;
  notes: string | null;
  status: "draft" | "published" | "archived";
  sourceUnansweredId: string | null;
  updatedAt: string | null;
};

function normalize(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function tokens(value: string): Set<string> {
  return new Set(
    normalize(value)
      .split(" ")
      .filter((token) => token.length >= 3),
  );
}

export function trainingMatchScore(message: string, utterance: string): number {
  const left = normalize(message);
  const right = normalize(utterance);
  if (!left || !right) return 0;
  if (left === right) return 100;
  if (left.includes(right) || right.includes(left)) return 70;
  const leftTokens = tokens(left);
  const rightTokens = tokens(right);
  const overlap = [...leftTokens].filter((token) => rightTokens.has(token)).length;
  return overlap === 0 ? 0 : Math.round((overlap / rightTokens.size) * 50);
}

function iso(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

function mapExample(
  id: string,
  data: FirebaseFirestore.DocumentData,
): SabiTrainingExample {
  return {
    id,
    utterance: String(data.utterance ?? ""),
    intent: String(data.intent ?? "answer_general"),
    clarification:
      typeof data.clarification === "string" ? data.clarification : null,
    suggestedPrompt: String(data.suggestedPrompt ?? ""),
    notes: typeof data.notes === "string" ? data.notes : null,
    status:
      data.status === "published" || data.status === "archived"
        ? data.status
        : "draft",
    sourceUnansweredId:
      typeof data.sourceUnansweredId === "string"
        ? data.sourceUnansweredId
        : null,
    updatedAt: iso(data.updatedAt),
  };
}

export async function findPublishedTrainingExamples(input: {
  businessId: string;
  message: string;
  limit?: number;
}): Promise<SabiTrainingExample[]> {
  const snap = await adminFirestore()
    .collection("businesses")
    .doc(input.businessId)
    .collection("sabi_training_examples")
    .where("status", "==", "published")
    .limit(50)
    .get();
  return snap.docs
    .map((doc) => ({
      example: mapExample(doc.id, doc.data()),
      score: trainingMatchScore(
        input.message,
        String(doc.data().utterance ?? ""),
      ),
    }))
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, input.limit ?? 5)
    .map((item) => item.example);
}

export async function listTrainingOverview(businessId: string): Promise<{
  examples: SabiTrainingExample[];
  unanswered: Array<Record<string, unknown>>;
}> {
  const db = adminFirestore();
  const business = db.collection("businesses").doc(businessId);
  const [examplesSnap, unansweredSnap] = await Promise.all([
    business.collection("sabi_training_examples").limit(100).get(),
    business.collection("sabi_unanswered").limit(100).get(),
  ]);
  const examples = examplesSnap.docs
    .map((doc) => mapExample(doc.id, doc.data()))
    .sort((a, b) => (b.updatedAt ?? "").localeCompare(a.updatedAt ?? ""));
  const unanswered = unansweredSnap.docs
    .map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        question: String(data.question ?? ""),
        count: Number(data.count ?? 1),
        status: String(data.status ?? "new"),
        lastAskedAt: iso(data.lastAskedAt),
      };
    })
    .sort((a, b) =>
      String(b.lastAskedAt ?? "").localeCompare(String(a.lastAskedAt ?? "")),
    );
  return {examples, unanswered};
}

export async function saveTrainingExample(input: {
  businessId: string;
  id?: string;
  utterance: string;
  intent: string;
  clarification: string | null;
  suggestedPrompt: string;
  notes: string | null;
  status: "draft" | "published" | "archived";
  sourceUnansweredId: string | null;
  actorId: string;
}): Promise<SabiTrainingExample> {
  const db = adminFirestore();
  const business = db.collection("businesses").doc(input.businessId);
  const ref = input.id
    ? business.collection("sabi_training_examples").doc(input.id)
    : business.collection("sabi_training_examples").doc();
  const existing = await ref.get();
  const payload = {
    businessId: input.businessId,
    utterance: input.utterance,
    utteranceNormalized: normalize(input.utterance),
    intent: input.intent,
    clarification: input.clarification,
    suggestedPrompt: input.suggestedPrompt,
    notes: input.notes,
    status: input.status,
    sourceUnansweredId: input.sourceUnansweredId,
    updatedBy: input.actorId,
    updatedAt: FieldValue.serverTimestamp(),
    ...(existing.exists
      ? {}
      : {createdBy: input.actorId, createdAt: FieldValue.serverTimestamp()}),
  };
  await ref.set(payload, {merge: true});
  await business.collection("sabi_training_audit").add({
    exampleId: ref.id,
    action: existing.exists ? "updated" : "created",
    status: input.status,
    actorId: input.actorId,
    createdAt: FieldValue.serverTimestamp(),
  });
  if (input.sourceUnansweredId) {
    await business
      .collection("sabi_unanswered")
      .doc(input.sourceUnansweredId)
      .set(
        {
          status: "trained",
          trainingExampleId: ref.id,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
  }
  const saved = await ref.get();
  return mapExample(saved.id, saved.data() ?? payload);
}

export async function updateTrainingStatus(input: {
  businessId: string;
  id: string;
  status: "draft" | "published" | "archived";
  actorId: string;
}): Promise<void> {
  const db = adminFirestore();
  const business = db.collection("businesses").doc(input.businessId);
  const ref = business.collection("sabi_training_examples").doc(input.id);
  const snap = await ref.get();
  if (!snap.exists) throw errors.notFound("Training example not found.");
  await Promise.all([
    ref.set(
      {
        status: input.status,
        updatedBy: input.actorId,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    ),
    business.collection("sabi_training_audit").add({
      exampleId: input.id,
      action: "status_changed",
      status: input.status,
      actorId: input.actorId,
      createdAt: FieldValue.serverTimestamp(),
    }),
  ]);
}
