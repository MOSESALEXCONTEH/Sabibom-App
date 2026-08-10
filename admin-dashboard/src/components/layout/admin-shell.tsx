"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import type { PlatformAdmin } from "@/lib/platform-admin/types";
import type { PlatformPermission } from "@/lib/permissions/registry";
import { AdminSidebar } from "@/components/layout/admin-sidebar";
import { Breadcrumbs } from "@/components/layout/breadcrumbs";
import { HeaderSearch } from "@/components/layout/header-search";
import { ADMIN_ERRORS } from "@/lib/auth/errors";

type Props = {
  admin: PlatformAdmin;
  permissions: PlatformPermission[];
  children: React.ReactNode;
};

export function AdminShell({ admin, permissions, children }: Props) {
  const router = useRouter();
  const [collapsed, setCollapsed] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const env = process.env.NEXT_PUBLIC_APP_ENV || "development";

  async function signOut() {
    setSigningOut(true);
    try {
      await fetch("/api/admin/session", { method: "DELETE" });
      router.replace("/login");
      router.refresh();
    } finally {
      setSigningOut(false);
    }
  }

  return (
    <div className="flex min-h-screen bg-surface-muted text-slate-900">
      <AdminSidebar
        permissions={permissions}
        collapsed={collapsed}
        onToggle={() => setCollapsed((v) => !v)}
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-14 items-center justify-between gap-3 border-b border-surface-border bg-white px-4">
          <div className="flex min-w-0 items-center gap-3">
            <h1 className="shrink-0 text-sm font-semibold text-slate-800">
              Platform administration
            </h1>
            {env !== "production" && (
              <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold uppercase text-amber-800">
                {env}
              </span>
            )}
            <HeaderSearch />
          </div>
          <div className="flex items-center gap-3">
            <div className="text-right">
              <p className="text-sm font-medium">
                {admin.displayName || admin.email || "Admin"}
              </p>
              <p className="text-xs text-slate-500">{admin.role}</p>
            </div>
            <button
              type="button"
              onClick={signOut}
              disabled={signingOut}
              className="rounded-md border border-surface-border bg-white px-3 py-1.5 text-sm font-medium hover:bg-surface-muted disabled:opacity-60"
            >
              {signingOut ? "Signing out…" : "Sign out"}
            </button>
          </div>
        </header>
        {admin.mfaRequired && (
          <div
            role="status"
            className="border-b border-amber-200 bg-amber-50 px-4 py-2 text-sm text-amber-900"
          >
            {ADMIN_ERRORS.mfaRequired} Complete MFA enrollment in Firebase
            Authentication before high-risk actions are allowed.
          </div>
        )}
        <main className="flex-1 overflow-auto p-6">
          <Breadcrumbs />
          {children}
        </main>
      </div>
    </div>
  );
}
