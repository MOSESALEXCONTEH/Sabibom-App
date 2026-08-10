import type { PlatformPermission } from "@/lib/permissions/registry";

export type NavItem = {
  label: string;
  href?: string;
  permission?: PlatformPermission;
  enabled: boolean;
};

export type NavSection = {
  title: string;
  items: NavItem[];
};

/** Full product nav — routes remain server-protected even when hidden. */
export const ADMIN_NAV: NavSection[] = [
  {
    title: "Overview",
    items: [
      {
        label: "Dashboard",
        href: "/dashboard",
        permission: "view_platform_dashboard",
        enabled: true,
      },
      {
        label: "Analytics",
        href: "/analytics",
        permission: "view_platform_analytics",
        enabled: true,
      },
      {
        label: "System Health",
        href: "/system-health",
        permission: "view_system_health",
        enabled: true,
      },
    ],
  },
  {
    title: "People",
    items: [
      { label: "Users", href: "/users", permission: "view_users", enabled: true },
      {
        label: "Businesses",
        href: "/businesses",
        permission: "view_businesses",
        enabled: true,
      },
      {
        label: "Platform Admins",
        href: "/admins",
        permission: "manage_platform_admins",
        enabled: true,
      },
      {
        label: "Beta Testers",
        href: "/beta-testers",
        permission: "manage_beta_testers",
        enabled: true,
      },
    ],
  },
  {
    title: "Support",
    items: [
      {
        label: "Feedback",
        href: "/feedback",
        permission: "view_feedback",
        enabled: true,
      },
      {
        label: "Support Tickets",
        href: "/support",
        permission: "view_support_tickets",
        enabled: true,
      },
      {
        label: "Bug Reports",
        href: "/bugs",
        permission: "view_bug_reports",
        enabled: true,
      },
    ],
  },
  {
    title: "Operations",
    items: [
      {
        label: "Backups",
        href: "/operations/backups",
        permission: "view_backup_jobs",
        enabled: true,
      },
      {
        label: "Restores",
        href: "/operations/restores",
        permission: "view_restore_jobs",
        enabled: true,
      },
      {
        label: "Imports",
        href: "/operations/imports",
        permission: "view_import_jobs",
        enabled: true,
      },
      {
        label: "Deletion Requests",
        href: "/operations/deletions",
        permission: "view_deletion_requests",
        enabled: true,
      },
      {
        label: "Notifications",
        href: "/notifications/send",
        permission: "send_platform_notifications",
        enabled: true,
      },
    ],
  },
  {
    title: "AI and Automation",
    items: [
      { label: "Sabi AI", href: "/ai", permission: "view_ai_metrics", enabled: true },
      {
        label: "AI Failures",
        href: "/ai/failures",
        permission: "view_ai_failures",
        enabled: true,
      },
      {
        label: "Provider Health",
        href: "/ai/providers",
        permission: "view_ai_provider_health",
        enabled: true,
      },
      {
        label: "Scheduled Jobs",
        href: "/system-health",
        permission: "view_system_health",
        enabled: true,
      },
    ],
  },
  {
    title: "Release Management",
    items: [
      {
        label: "App Versions",
        href: "/releases",
        permission: "manage_app_versions",
        enabled: true,
      },
      {
        label: "Feature Flags",
        href: "/feature-flags",
        permission: "manage_feature_flags",
        enabled: true,
      },
      {
        label: "Announcements",
        href: "/announcements",
        permission: "manage_announcements",
        enabled: true,
      },
      {
        label: "Maintenance Mode",
        href: "/maintenance",
        permission: "manage_maintenance_mode",
        enabled: true,
      },
      {
        label: "Release Readiness",
        href: "/release-readiness",
        permission: "view_release_readiness",
        enabled: true,
      },
    ],
  },
  {
    title: "Security",
    items: [
      {
        label: "Security Logs",
        href: "/security",
        permission: "view_security_logs",
        enabled: true,
      },
      {
        label: "Authentication Events",
        href: "/security/auth-events",
        permission: "view_auth_events",
        enabled: true,
      },
      {
        label: "App Check",
        href: "/security/app-check",
        permission: "view_app_check_events",
        enabled: true,
      },
      {
        label: "Rate Limits",
        href: "/security/rate-limits",
        permission: "view_rate_limit_events",
        enabled: true,
      },
      {
        label: "Admin Activity",
        href: "/security/admin-activity",
        permission: "view_security_logs",
        enabled: true,
      },
    ],
  },
  {
    title: "Billing",
    items: [
      {
        label: "Plans",
        href: "/billing/plans",
        permission: "manage_subscription_plans",
        enabled: true,
      },
      {
        label: "Subscriptions",
        href: "/billing/subscriptions",
        permission: "view_subscriptions",
        enabled: true,
      },
      {
        label: "Billing Events",
        href: "/billing/events",
        permission: "view_billing_events",
        enabled: true,
      },
    ],
  },
  {
    title: "Settings",
    items: [
      {
        label: "Platform Settings",
        href: "/settings/platform",
        permission: "manage_platform_settings",
        enabled: true,
      },
      {
        label: "My Admin Profile",
        href: "/settings/profile",
        enabled: true,
      },
    ],
  },
];
