import Link from "next/link";
import { ADMIN_ERRORS } from "@/lib/auth/errors";

export default function SessionExpiredPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-surface-muted px-4">
      <div className="max-w-lg rounded-2xl border border-surface-border bg-white p-8 text-center shadow-sm">
        <h1 className="text-xl font-bold text-slate-900">Session expired</h1>
        <p className="mt-3 text-sm text-slate-600">
          {ADMIN_ERRORS.unauthenticated}
        </p>
        <Link
          href="/login"
          className="mt-6 inline-flex rounded-lg bg-brand px-4 py-2 text-sm font-semibold text-white hover:bg-brand-dark"
        >
          Sign in again
        </Link>
      </div>
    </div>
  );
}
