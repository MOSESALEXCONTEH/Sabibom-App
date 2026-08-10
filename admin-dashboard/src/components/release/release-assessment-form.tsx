"use client";

import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

type Props = {
  initial: {
    decision: string;
    notes: string | null;
    evidence: string[];
    checklist: {
      criticalBugsCleared?: boolean;
      betaSignoff?: boolean;
      rollbackPlanReady?: boolean;
      monitoringReady?: boolean;
    };
    goBlockedReasons: string[];
  };
};

export function ReleaseAssessmentForm({ initial }: Props) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [decision, setDecision] = useState(initial.decision || "pending");
  const [notes, setNotes] = useState(initial.notes ?? "");
  const [evidenceText, setEvidenceText] = useState(
    initial.evidence.join("\n"),
  );
  const [criticalBugsCleared, setCriticalBugsCleared] = useState(
    initial.checklist.criticalBugsCleared === true,
  );
  const [betaSignoff, setBetaSignoff] = useState(
    initial.checklist.betaSignoff === true,
  );
  const [rollbackPlanReady, setRollbackPlanReady] = useState(
    initial.checklist.rollbackPlanReady === true,
  );
  const [monitoringReady, setMonitoringReady] = useState(
    initial.checklist.monitoringReady === true,
  );

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const evidence = evidenceText
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean);
      const res = await fetch("/api/admin/release-readiness", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          decision,
          notes: notes || null,
          evidence,
          checklist: {
            criticalBugsCleared,
            betaSignoff,
            rollbackPlanReady,
            monitoringReady,
          },
        }),
      });
      const json = (await res.json().catch(() => ({}))) as {
        error?: { message?: string };
      };
      if (!res.ok) throw new Error(json.error?.message || "Save failed");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Save failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form
      onSubmit={onSubmit}
      className="space-y-4 rounded-xl border border-surface-border bg-white p-5"
    >
      <h3 className="text-sm font-semibold text-slate-900">
        Save assessment (manual Go/No-Go)
      </h3>
      <p className="text-xs text-slate-500">
        Go is never auto-set. Choosing Go requires evidence and cleared blockers.
      </p>

      <div>
        <label htmlFor="rr-decision" className="mb-1 block text-xs font-medium text-slate-600">
          Decision
        </label>
        <select
          id="rr-decision"
          name="decision"
          value={decision}
          onChange={(e) => setDecision(e.target.value)}
          className="w-full max-w-xs rounded-md border border-surface-border px-3 py-2 text-sm"
        >
          <option value="pending">Pending</option>
          <option value="no_go">No-Go</option>
          <option value="go">Go</option>
        </select>
      </div>

      <div>
        <label htmlFor="rr-notes" className="mb-1 block text-xs font-medium text-slate-600">
          Assessment notes
        </label>
        <textarea
          id="rr-notes"
          name="notes"
          rows={4}
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          className="w-full rounded-md border border-surface-border px-3 py-2 text-sm"
        />
      </div>

      <div>
        <label htmlFor="rr-evidence" className="mb-1 block text-xs font-medium text-slate-600">
          Evidence (one item per line)
        </label>
        <textarea
          id="rr-evidence"
          name="evidence"
          rows={4}
          value={evidenceText}
          onChange={(e) => setEvidenceText(e.target.value)}
          className="w-full rounded-md border border-surface-border px-3 py-2 text-sm"
          placeholder="Beta sign-off link&#10;Staging soak results&#10;Rollback dry-run complete"
        />
      </div>

      <fieldset className="space-y-2">
        <legend className="text-xs font-medium text-slate-600">Checklist</legend>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={criticalBugsCleared}
            onChange={(e) => setCriticalBugsCleared(e.target.checked)}
          />
          Critical bugs cleared
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={betaSignoff}
            onChange={(e) => setBetaSignoff(e.target.checked)}
          />
          Beta sign-off
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={rollbackPlanReady}
            onChange={(e) => setRollbackPlanReady(e.target.checked)}
          />
          Rollback plan ready
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={monitoringReady}
            onChange={(e) => setMonitoringReady(e.target.checked)}
          />
          Monitoring ready
        </label>
      </fieldset>

      {initial.goBlockedReasons.length > 0 ? (
        <ul className="list-disc space-y-1 rounded-md bg-amber-50 px-4 py-3 text-sm text-amber-900">
          {initial.goBlockedReasons.map((reason) => (
            <li key={reason}>{reason}</li>
          ))}
        </ul>
      ) : null}

      {error ? <p className="text-sm text-rose-600">{error}</p> : null}
      <button
        type="submit"
        disabled={busy}
        className="rounded-md border border-brand bg-brand px-3 py-1.5 text-sm font-medium text-white disabled:opacity-60"
      >
        {busy ? "Saving…" : "Save assessment"}
      </button>
    </form>
  );
}
