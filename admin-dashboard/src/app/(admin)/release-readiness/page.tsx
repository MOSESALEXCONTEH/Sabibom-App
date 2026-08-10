import { requirePlatformPermission } from "@/lib/auth/session";
import { getReleaseReadiness } from "@/lib/release-readiness/repository";
import { PageHeader } from "@/components/ui/page-header";
import { StatCard } from "@/components/ui/stat-card";
import { StatusBadge } from "@/components/ui/status-badge";
import { ReleaseAssessmentForm } from "@/components/release/release-assessment-form";
import { formatDate } from "@/lib/utils/serialize";

export default async function ReleaseReadinessPage() {
  await requirePlatformPermission("view_release_readiness");
  const readiness = await getReleaseReadiness();

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <PageHeader
        eyebrow="Release"
        title="Release readiness"
        description="Aggregates open P0/P1 bugs and stored assessment. Go is never auto-set without evidence."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Decision" value={String(readiness.decision)} />
        <StatCard
          label="Suggested"
          value={readiness.suggestedDecision}
          hint="Suggestion only — not auto-applied"
        />
        <StatCard label="Open P0" value={readiness.openP0Count} />
        <StatCard label="Open P1" value={readiness.openP1Count} />
      </div>

      <div className="rounded-xl border border-surface-border bg-white p-5 text-sm">
        <div className="flex flex-wrap items-center gap-3">
          <StatusBadge value={readiness.decision} />
          <span className="text-slate-500">
            Last assessed {formatDate(readiness.assessedAt)}
            {readiness.assessedBy ? ` by ${readiness.assessedBy}` : ""}
          </span>
        </div>
        {readiness.notes ? (
          <p className="mt-3 whitespace-pre-wrap text-slate-700">
            {readiness.notes}
          </p>
        ) : (
          <p className="mt-3 text-slate-500">No assessment notes saved yet.</p>
        )}
      </div>

      <ReleaseAssessmentForm
        initial={{
          decision: readiness.decision,
          notes: readiness.notes,
          evidence: readiness.evidence,
          checklist: readiness.checklist,
          goBlockedReasons: readiness.goBlockedReasons,
        }}
      />
    </div>
  );
}
