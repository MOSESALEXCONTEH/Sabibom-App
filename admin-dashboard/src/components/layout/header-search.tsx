"use client";

import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

export function HeaderSearch() {
  const router = useRouter();
  const [q, setQ] = useState("");

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    const trimmed = q.trim();
    if (trimmed.length < 2) return;
    router.push(`/search?q=${encodeURIComponent(trimmed)}`);
  }

  return (
    <form onSubmit={onSubmit} className="hidden items-center gap-2 md:flex">
      <label htmlFor="admin-global-search" className="sr-only">
        Search users, businesses, tickets
      </label>
      <input
        id="admin-global-search"
        name="q"
        type="search"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Search…"
        minLength={2}
        maxLength={100}
        className="w-48 rounded-md border border-surface-border bg-white px-3 py-1.5 text-sm outline-none ring-brand focus:ring-2 lg:w-64"
      />
      <button
        type="submit"
        className="rounded-md border border-surface-border bg-white px-2.5 py-1.5 text-xs font-medium text-slate-700 hover:bg-surface-muted"
      >
        Search
      </button>
    </form>
  );
}
