"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ADMIN_NAV } from "@/lib/navigation/admin-nav";
import type { PlatformPermission } from "@/lib/permissions/registry";
import { cn } from "@/lib/utils/cn";

type Props = {
  permissions: PlatformPermission[];
  collapsed: boolean;
  onToggle: () => void;
};

export function AdminSidebar({ permissions, collapsed, onToggle }: Props) {
  const pathname = usePathname();
  const can = (permission?: PlatformPermission) =>
    !permission || permissions.includes(permission);

  return (
    <aside
      className={cn(
        "flex h-full flex-col border-r border-surface-border bg-white transition-[width]",
        collapsed ? "w-[72px]" : "w-64",
      )}
    >
      <div className="flex h-14 items-center justify-between border-b border-surface-border px-3">
        {!collapsed && (
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-brand">
              SabiBom
            </p>
            <p className="text-sm font-bold text-slate-900">Super Admin</p>
          </div>
        )}
        <button
          type="button"
          onClick={onToggle}
          className="rounded-md border border-surface-border px-2 py-1 text-xs text-slate-600 hover:bg-surface-muted"
          aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
        >
          {collapsed ? "»" : "«"}
        </button>
      </div>
      <nav className="flex-1 overflow-y-auto p-2" aria-label="Admin">
        {ADMIN_NAV.map((section) => (
          <div key={section.title} className="mb-4">
            {!collapsed && (
              <p className="mb-1 px-2 text-[11px] font-semibold uppercase tracking-wide text-slate-400">
                {section.title}
              </p>
            )}
            <ul className="space-y-0.5">
              {section.items.map((item) => {
                const allowed = can(item.permission);
                const active = item.href && pathname.startsWith(item.href);
                if (!allowed) return null;
                if (!item.enabled || !item.href) {
                  return (
                    <li key={item.label}>
                      <span
                        className={cn(
                          "block cursor-not-allowed rounded-md px-2 py-1.5 text-sm text-slate-400",
                          collapsed && "text-center text-xs",
                        )}
                        title="Coming in a later checkpoint"
                      >
                        {collapsed ? item.label.slice(0, 1) : item.label}
                      </span>
                    </li>
                  );
                }
                return (
                  <li key={item.label}>
                    <Link
                      href={item.href}
                      className={cn(
                        "block rounded-md px-2 py-1.5 text-sm font-medium",
                        active
                          ? "bg-brand-muted text-brand-dark"
                          : "text-slate-700 hover:bg-surface-muted",
                        collapsed && "text-center text-xs",
                      )}
                    >
                      {collapsed ? item.label.slice(0, 1) : item.label}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </nav>
    </aside>
  );
}
