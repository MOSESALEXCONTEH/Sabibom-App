"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";

type Props = {
  label: string;
  confirm?: string;
  method?: "POST" | "PATCH" | "DELETE";
  href: string;
  body?: Record<string, unknown>;
  variant?: "default" | "danger" | "primary";
  disabled?: boolean;
};

export function ActionButton({
  label,
  confirm,
  method = "POST",
  href,
  body,
  variant = "default",
  disabled,
}: Props) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);

  async function run() {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(href, {
        method,
        headers: { "Content-Type": "application/json" },
        body: body ? JSON.stringify(body) : undefined,
      });
      const json = (await res.json().catch(() => ({}))) as {
        error?: { message?: string };
      };
      if (!res.ok) {
        throw new Error(json.error?.message || "Request failed");
      }
      setDialogOpen(false);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Request failed");
    } finally {
      setBusy(false);
    }
  }

  function onClick() {
    if (confirm) {
      setDialogOpen(true);
      return;
    }
    void run();
  }

  const styles =
    variant === "danger"
      ? "border-rose-200 bg-rose-50 text-rose-800 hover:bg-rose-100"
      : variant === "primary"
        ? "border-brand bg-brand text-white hover:opacity-90"
        : "border-surface-border bg-white text-slate-800 hover:bg-surface-muted";

  return (
    <span className="inline-flex flex-col items-start gap-1">
      <button
        type="button"
        onClick={onClick}
        disabled={disabled || busy}
        className={`rounded-md border px-3 py-1.5 text-sm font-medium disabled:opacity-60 ${styles}`}
      >
        {busy ? "Working…" : label}
      </button>
      {error ? <span className="text-xs text-rose-600">{error}</span> : null}
      {confirm ? (
        <ConfirmDialog
          open={dialogOpen}
          title={label}
          description={confirm}
          confirmLabel={label}
          danger={variant === "danger"}
          busy={busy}
          onConfirm={() => void run()}
          onCancel={() => setDialogOpen(false)}
        />
      ) : null}
    </span>
  );
}
