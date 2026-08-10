"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const LABELS: Record<string, string> = {
  dashboard: "Dashboard",
  users: "Users",
  businesses: "Businesses",
  admins: "Platform Admins",
  "beta-testers": "Beta Testers",
  feedback: "Feedback",
  support: "Support Tickets",
  bugs: "Bug Reports",
  analytics: "Analytics",
  "system-health": "System Health",
  operations: "Operations",
  backups: "Backups",
  restores: "Restores",
  imports: "Imports",
  deletions: "Deletion Requests",
  notifications: "Notifications",
  send: "Send",
  ai: "Sabi AI",
  failures: "Failures",
  providers: "Providers",
  releases: "App Versions",
  "feature-flags": "Feature Flags",
  announcements: "Announcements",
  maintenance: "Maintenance Mode",
  "release-readiness": "Release Readiness",
  security: "Security",
  "auth-events": "Authentication Events",
  "app-check": "App Check",
  "rate-limits": "Rate Limits",
  "admin-activity": "Admin Activity",
  billing: "Billing",
  plans: "Plans",
  subscriptions: "Subscriptions",
  events: "Billing Events",
  settings: "Settings",
  platform: "Platform Settings",
  profile: "My Admin Profile",
  search: "Search",
};

function labelFor(segment: string): string {
  return LABELS[segment] ?? segment.replaceAll("-", " ");
}

export function Breadcrumbs() {
  const pathname = usePathname() || "/";
  const parts = pathname.split("/").filter(Boolean);
  if (parts.length === 0) return null;

  const crumbs = parts.map((part, index) => {
    const href = `/${parts.slice(0, index + 1).join("/")}`;
    const isLast = index === parts.length - 1;
    return { href, label: labelFor(part), isLast };
  });

  return (
    <nav aria-label="Breadcrumb" className="mb-4">
      <ol className="flex flex-wrap items-center gap-1 text-xs text-slate-500">
        <li>
          <Link href="/dashboard" className="hover:text-brand">
            Home
          </Link>
        </li>
        {crumbs.map((crumb) => (
          <li key={crumb.href} className="flex items-center gap-1">
            <span aria-hidden="true">/</span>
            {crumb.isLast ? (
              <span className="font-medium text-slate-700" aria-current="page">
                {crumb.label}
              </span>
            ) : (
              <Link href={crumb.href} className="hover:text-brand">
                {crumb.label}
              </Link>
            )}
          </li>
        ))}
      </ol>
    </nav>
  );
}
