import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { adminFirestore } from "@/lib/firebase/admin";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS, SETTINGS_DOCS } from "@/lib/platform/collections";
import { writeAdminActivity } from "@/lib/platform-admin/repository";
import { AdminHttpError } from "@/lib/auth/errors";

export const RELEASE_DECISIONS = ["pending", "no_go", "go"] as const;

export const releaseAssessmentSchema = z.object({
  decision: z.enum(RELEASE_DECISIONS),
  notes: z.string().trim().max(5000).optional().nullable(),
  evidence: z.array(z.string().trim().min(1).max(500)).max(20).default([]),
  checklist: z
    .object({
      criticalBugsCleared: z.boolean().optional(),
      betaSignoff: z.boolean().optional(),
      rollbackPlanReady: z.boolean().optional(),
      monitoringReady: z.boolean().optional(),
    })
    .default({}),
});

export type ReleaseAssessmentInput = z.infer<typeof releaseAssessmentSchema>;

export type ReleaseReadiness = {
  decision: (typeof RELEASE_DECISIONS)[number] | string;
  notes: string | null;
  evidence: string[];
  checklist: {
    criticalBugsCleared?: boolean;
    betaSignoff?: boolean;
    rollbackPlanReady?: boolean;
    monitoringReady?: boolean;
  };
  openP0Count: number;
  openP1Count: number;
  suggestedDecision: "no_go" | "go" | "pending";
  assessedBy: string | null;
  assessedAt: Date | null;
  updatedAt: Date | null;
  goBlockedReasons: string[];
};

function isOpenBugStatus(status: string): boolean {
  const s = status.toLowerCase();
  return !["resolved", "closed", "done", "wontfix", "duplicate"].includes(s);
}

function isP0(value: unknown): boolean {
  if (typeof value !== "string") return false;
  const v = value.toLowerCase();
  return v === "p0" || v === "critical" || v === "blocker";
}

function isP1(value: unknown): boolean {
  if (typeof value !== "string") return false;
  const v = value.toLowerCase();
  return v === "p1" || v === "high";
}

export async function countOpenHighSeverityBugs(): Promise<{
  openP0Count: number;
  openP1Count: number;
}> {
  try {
    const snap = await adminFirestore()
      .collection(COLLECTIONS.bugReports)
      .limit(200)
      .get();
    let openP0Count = 0;
    let openP1Count = 0;
    for (const doc of snap.docs) {
      const data = doc.data() ?? {};
      const status =
        typeof data.status === "string" ? data.status : "open";
      if (!isOpenBugStatus(status)) continue;
      const severity = data.severity ?? data.priority;
      if (isP0(severity)) openP0Count += 1;
      else if (isP1(severity)) openP1Count += 1;
    }
    return { openP0Count, openP1Count };
  } catch {
    return { openP0Count: 0, openP1Count: 0 };
  }
}

export function computeGoBlockedReasons(input: {
  openP0Count: number;
  openP1Count: number;
  notes?: string | null;
  evidence?: string[];
  checklist?: ReleaseAssessmentInput["checklist"];
}): string[] {
  const reasons: string[] = [];
  if (input.openP0Count > 0) {
    reasons.push(`${input.openP0Count} open P0/critical bug(s)`);
  }
  if (input.openP1Count > 3) {
    reasons.push(`${input.openP1Count} open P1/high bug(s) (threshold 3)`);
  }
  const evidence = input.evidence ?? [];
  if (evidence.length === 0 && !(input.notes && input.notes.trim().length >= 20)) {
    reasons.push("Missing evidence notes (need evidence items or notes ≥ 20 chars)");
  }
  const checklist = input.checklist ?? {};
  if (checklist.criticalBugsCleared !== true) {
    reasons.push("Checklist: critical bugs not cleared");
  }
  if (checklist.rollbackPlanReady !== true) {
    reasons.push("Checklist: rollback plan not ready");
  }
  return reasons;
}

/** Never auto-select go — suggestion stays no_go/pending without evidence. */
export function suggestDecision(input: {
  openP0Count: number;
  openP1Count: number;
  notes?: string | null;
  evidence?: string[];
  checklist?: ReleaseAssessmentInput["checklist"];
}): "no_go" | "go" | "pending" {
  const blocked = computeGoBlockedReasons(input);
  if (blocked.length > 0) {
    if (input.openP0Count > 0) return "no_go";
    return "pending";
  }
  // Evidence present and bugs clear — still only a suggestion; never auto-write go.
  return "go";
}

export async function getReleaseReadiness(): Promise<ReleaseReadiness> {
  const [{ openP0Count, openP1Count }, snap] = await Promise.all([
    countOpenHighSeverityBugs(),
    adminFirestore()
      .collection(COLLECTIONS.platformSettings)
      .doc(SETTINGS_DOCS.releaseReadiness)
      .get(),
  ]);

  const data = snap.exists ? snap.data() ?? {} : {};
  const notes = typeof data.notes === "string" ? data.notes : null;
  const evidence = Array.isArray(data.evidence)
    ? data.evidence.filter((x): x is string => typeof x === "string")
    : [];
  const checklist =
    data.checklist && typeof data.checklist === "object"
      ? (data.checklist as ReleaseReadiness["checklist"])
      : {};

  const goBlockedReasons = computeGoBlockedReasons({
    openP0Count,
    openP1Count,
    notes,
    evidence,
    checklist,
  });

  const storedDecision =
    typeof data.decision === "string" ? data.decision : "pending";

  // Never treat missing/auto state as go.
  const decision =
    storedDecision === "go" && goBlockedReasons.length > 0
      ? "no_go"
      : storedDecision === "go" ||
          storedDecision === "no_go" ||
          storedDecision === "pending"
        ? storedDecision
        : "pending";

  return {
    decision,
    notes,
    evidence,
    checklist,
    openP0Count,
    openP1Count,
    suggestedDecision: suggestDecision({
      openP0Count,
      openP1Count,
      notes,
      evidence,
      checklist,
    }),
    assessedBy: typeof data.assessedBy === "string" ? data.assessedBy : null,
    assessedAt: asDate(data.assessedAt),
    updatedAt: asDate(data.updatedAt),
    goBlockedReasons,
  };
}

export async function saveReleaseAssessment(input: {
  assessment: ReleaseAssessmentInput;
  actorUid: string;
  actorName: string | null;
  actorRole: string;
  requestId?: string | null;
}): Promise<ReleaseReadiness> {
  const { openP0Count, openP1Count } = await countOpenHighSeverityBugs();
  const blocked = computeGoBlockedReasons({
    openP0Count,
    openP1Count,
    notes: input.assessment.notes,
    evidence: input.assessment.evidence,
    checklist: input.assessment.checklist,
  });

  if (input.assessment.decision === "go" && blocked.length > 0) {
    throw new AdminHttpError(
      400,
      `Cannot set Go: ${blocked.join("; ")}`,
      "invalid_argument",
    );
  }

  const ref = adminFirestore()
    .collection(COLLECTIONS.platformSettings)
    .doc(SETTINGS_DOCS.releaseReadiness);

  const previous = await getReleaseReadiness();
  await ref.set(
    {
      decision: input.assessment.decision,
      notes: input.assessment.notes ?? null,
      evidence: input.assessment.evidence,
      checklist: input.assessment.checklist,
      openP0Count,
      openP1Count,
      assessedBy: input.actorUid,
      assessedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: input.actorUid,
    },
    { merge: true },
  );

  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType: "save_release_assessment",
    targetType: "release_readiness",
    targetId: SETTINGS_DOCS.releaseReadiness,
    description: `Saved release assessment as ${input.assessment.decision}`,
    previousStateSnapshot: {
      decision: previous.decision,
      openP0Count: previous.openP0Count,
      openP1Count: previous.openP1Count,
    },
    newStateSnapshot: {
      decision: input.assessment.decision,
      openP0Count,
      openP1Count,
    },
    requestId: input.requestId ?? null,
  });

  return getReleaseReadiness();
}
