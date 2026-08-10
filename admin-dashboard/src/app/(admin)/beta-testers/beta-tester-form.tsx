"use client";

import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

export function BetaTesterForm() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const form = new FormData(e.currentTarget);
    try {
      const res = await fetch("/api/admin/beta-testers", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: String(form.get("email") ?? ""),
          displayName: String(form.get("displayName") ?? "") || null,
          platform: String(form.get("platform") ?? "all"),
          notes: String(form.get("notes") ?? "") || null,
        }),
      });
      const json = (await res.json().catch(() => ({}))) as {
        error?: { message?: string };
      };
      if (!res.ok) throw new Error(json.error?.message || "Failed to invite");
      e.currentTarget.reset();
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
      className="rounded-xl border border-surface-border bg-white p-5"
    >
      <h3 className="text-sm font-semibold text-slate-900">Invite beta tester</h3>
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor="beta-email" className="block text-xs font-medium text-slate-600">
            Email
          </label>
          <input
            id="beta-email"
            name="email"
            type="email"
            required
            className="mt-1 w-full rounded-md border border-surface-border px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="beta-name" className="block text-xs font-medium text-slate-600">
            Display name
          </label>
          <input
            id="beta-name"
            name="displayName"
            type="text"
            className="mt-1 w-full rounded-md border border-surface-border px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="beta-platform" className="block text-xs font-medium text-slate-600">
            Platform
          </label>
          <select
            id="beta-platform"
            name="platform"
            defaultValue="all"
            className="mt-1 w-full rounded-md border border-surface-border px-3 py-2 text-sm"
          >
            <option value="all">All</option>
            <option value="ios">iOS</option>
            <option value="android">Android</option>
            <option value="web">Web</option>
          </select>
        </div>
        <div>
          <label htmlFor="beta-notes" className="block text-xs font-medium text-slate-600">
            Notes
          </label>
          <input
            id="beta-notes"
            name="notes"
            type="text"
            className="mt-1 w-full rounded-md border border-surface-border px-3 py-2 text-sm"
          />
        </div>
      </div>
      {error ? <p className="mt-3 text-sm text-rose-600">{error}</p> : null}
      <button
        type="submit"
        disabled={busy}
        className="mt-4 rounded-md border border-brand bg-brand px-3 py-1.5 text-sm font-medium text-white disabled:opacity-60"
      >
        {busy ? "Inviting…" : "Invite tester"}
      </button>
    </form>
  );
}
