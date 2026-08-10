"use client";

import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

export function BetaTesterForm() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [platform, setPlatform] = useState("all");
  const [notes, setNotes] = useState("");

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/admin/beta-testers", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          displayName: displayName || null,
          platform,
          notes: notes || null,
        }),
      });
      const json = (await res.json().catch(() => ({}))) as {
        error?: { message?: string };
      };
      if (!res.ok) throw new Error(json.error?.message || "Failed to invite");
      setEmail("");
      setDisplayName("");
      setNotes("");
      setPlatform("all");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to invite");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form
      onSubmit={onSubmit}
      className="space-y-3 rounded-xl border border-surface-border bg-white p-5"
    >
      <h3 className="text-sm font-semibold text-slate-900">Invite beta tester</h3>
      <div className="grid gap-3 sm:grid-cols-2">
        <div>
          <label htmlFor="beta-email" className="mb-1 block text-xs font-medium text-slate-600">
            Email
          </label>
          <input
            id="beta-email"
            name="email"
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full rounded-md border border-surface-border px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="beta-name" className="mb-1 block text-xs font-medium text-slate-600">
            Display name
          </label>
          <input
            id="beta-name"
            name="displayName"
            type="text"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            className="w-full rounded-md border border-surface-border px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="beta-platform" className="mb-1 block text-xs font-medium text-slate-600">
            Platform
          </label>
          <select
            id="beta-platform"
            name="platform"
            value={platform}
            onChange={(e) => setPlatform(e.target.value)}
            className="w-full rounded-md border border-surface-border px-3 py-2 text-sm"
          >
            <option value="all">All</option>
            <option value="android">Android</option>
            <option value="ios">iOS</option>
            <option value="web">Web</option>
          </select>
        </div>
        <div>
          <label htmlFor="beta-notes" className="mb-1 block text-xs font-medium text-slate-600">
            Notes
          </label>
          <input
            id="beta-notes"
            name="notes"
            type="text"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            className="w-full rounded-md border border-surface-border px-3 py-2 text-sm"
          />
        </div>
      </div>
      {error ? <p className="text-sm text-rose-600">{error}</p> : null}
      <button
        type="submit"
        disabled={busy}
        className="rounded-md border border-brand bg-brand px-3 py-1.5 text-sm font-medium text-white disabled:opacity-60"
      >
        {busy ? "Inviting…" : "Invite tester"}
      </button>
    </form>
  );
}
