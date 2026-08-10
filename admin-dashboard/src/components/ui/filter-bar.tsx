"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { useTransition } from "react";

type FilterOption = { label: string; value: string };

type Props = {
  searchPlaceholder?: string;
  filters?: { key: string; label: string; options: FilterOption[] }[];
};

export function FilterBar({
  searchPlaceholder = "Search…",
  filters = [],
}: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [pending, startTransition] = useTransition();

  function update(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (!value) params.delete(key);
    else params.set(key, value);
    params.delete("cursor");
    startTransition(() => {
      router.push(`${pathname}?${params.toString()}`);
    });
  }

  return (
    <form
      className="mb-4 flex flex-wrap items-end gap-3"
      onSubmit={(e) => {
        e.preventDefault();
        const fd = new FormData(e.currentTarget);
        update("q", String(fd.get("q") ?? ""));
      }}
    >
      <label className="flex min-w-[220px] flex-1 flex-col gap-1 text-xs font-semibold text-slate-500">
        Search
        <input
          name="q"
          defaultValue={searchParams.get("q") ?? ""}
          placeholder={searchPlaceholder}
          className="rounded-md border border-surface-border bg-white px-3 py-2 text-sm font-normal text-slate-800"
        />
      </label>
      {filters.map((filter) => (
        <label
          key={filter.key}
          className="flex flex-col gap-1 text-xs font-semibold text-slate-500"
        >
          {filter.label}
          <select
            defaultValue={searchParams.get(filter.key) ?? ""}
            onChange={(e) => update(filter.key, e.target.value)}
            className="rounded-md border border-surface-border bg-white px-3 py-2 text-sm font-normal text-slate-800"
          >
            <option value="">All</option>
            {filter.options.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </label>
      ))}
      <button
        type="submit"
        disabled={pending}
        className="rounded-md border border-brand bg-brand px-3 py-2 text-sm font-medium text-white disabled:opacity-60"
      >
        {pending ? "Applying…" : "Apply"}
      </button>
    </form>
  );
}
