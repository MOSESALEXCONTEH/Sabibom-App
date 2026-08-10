"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export function GlobalSearch() {
  const router = useRouter();
  const [q, setQ] = useState("");

  return (
    <form
      role="search"
      className="hidden min-w-[220px] max-w-md flex-1 md:block"
      onSubmit={(e) => {
        e.preventDefault();
        const value = q.trim();
        if (!value) return;
        router.push(`/search?q=${encodeURIComponent(value)}`);
      }}
    >
      <label className="sr-only" htmlFor="admin-global-search">
        Search admin records
      </label>
      <input
        id="admin-global-search"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Search users, businesses, tickets…"
        className="w-full rounded-md border border-surface-border bg-surface-muted px-3 py-1.5 text-sm"
      />
    </form>
  );
}
