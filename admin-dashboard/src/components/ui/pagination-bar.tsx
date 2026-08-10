import Link from "next/link";

type Props = {
  basePath: string;
  nextCursor: string | null;
  searchParams?: Record<string, string | undefined>;
};

export function PaginationBar({ basePath, nextCursor, searchParams = {} }: Props) {
  if (!nextCursor) return null;

  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(searchParams)) {
    if (value) params.set(key, value);
  }
  params.set("cursor", nextCursor);

  return (
    <div className="mt-4 flex justify-end">
      <Link
        href={`${basePath}?${params.toString()}`}
        className="rounded-md border border-surface-border bg-white px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-surface-muted"
      >
        Next page
      </Link>
    </div>
  );
}
