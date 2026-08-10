import { requirePlatformPermission } from "@/lib/auth/session";

export default async function DashboardPage() {
  const ctx = await requirePlatformPermission("view_platform_dashboard");

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wide text-brand">
          Checkpoint 1
        </p>
        <h2 className="mt-1 text-2xl font-bold text-slate-900">
          Admin foundation ready
        </h2>
        <p className="mt-2 max-w-2xl text-sm text-slate-600">
          Secure session cookies, platform-admin verification, and the
          permission registry are active. Metrics, users, businesses, and
          support tools arrive in later checkpoints.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="rounded-xl border border-surface-border bg-white p-5">
          <p className="text-xs font-semibold uppercase text-slate-400">
            Signed in as
          </p>
          <p className="mt-2 text-lg font-semibold">
            {ctx.admin.displayName || ctx.email || ctx.uid}
          </p>
          <p className="text-sm text-slate-500">{ctx.admin.role}</p>
        </div>
        <div className="rounded-xl border border-surface-border bg-white p-5">
          <p className="text-xs font-semibold uppercase text-slate-400">
            Effective permissions
          </p>
          <p className="mt-2 text-3xl font-bold text-brand">
            {ctx.permissions.length}
          </p>
          <p className="text-sm text-slate-500">
            Resolved from role defaults and stored grants
          </p>
        </div>
      </div>

      <div className="rounded-xl border border-dashed border-slate-300 bg-white p-5 text-sm text-slate-600">
        Sidebar items for later checkpoints are visible when permitted but
        disabled until those modules ship. Routes and APIs remain server-protected.
      </div>
    </div>
  );
}
