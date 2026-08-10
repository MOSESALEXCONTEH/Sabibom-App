import { cn } from "@/lib/utils/cn";

const TONES: Record<string, string> = {
  active: "bg-emerald-50 text-emerald-800 border-emerald-200",
  new: "bg-sky-50 text-sky-800 border-sky-200",
  open: "bg-sky-50 text-sky-800 border-sky-200",
  pending: "bg-amber-50 text-amber-900 border-amber-200",
  reviewing: "bg-amber-50 text-amber-900 border-amber-200",
  in_progress: "bg-amber-50 text-amber-900 border-amber-200",
  resolved: "bg-emerald-50 text-emerald-800 border-emerald-200",
  closed: "bg-slate-100 text-slate-700 border-slate-200",
  archived: "bg-slate-100 text-slate-700 border-slate-200",
  disabled: "bg-rose-50 text-rose-800 border-rose-200",
  suspended: "bg-rose-50 text-rose-800 border-rose-200",
  failed: "bg-rose-50 text-rose-800 border-rose-200",
  completed: "bg-emerald-50 text-emerald-800 border-emerald-200",
  approved: "bg-emerald-50 text-emerald-800 border-emerald-200",
  rejected: "bg-rose-50 text-rose-800 border-rose-200",
  maintenance: "bg-amber-50 text-amber-900 border-amber-200",
  true: "bg-emerald-50 text-emerald-800 border-emerald-200",
  false: "bg-slate-100 text-slate-700 border-slate-200",
};

type Props = {
  value: string | boolean | null | undefined;
  className?: string;
};

export function StatusBadge({ value, className }: Props) {
  const raw =
    value === true ? "true" : value === false ? "false" : (value ?? "unknown");
  const key = String(raw).toLowerCase();
  return (
    <span
      className={cn(
        "inline-flex rounded-md border px-2 py-0.5 text-xs font-semibold capitalize",
        TONES[key] ?? "bg-slate-100 text-slate-700 border-slate-200",
        className,
      )}
    >
      {String(raw).replaceAll("_", " ")}
    </span>
  );
}
