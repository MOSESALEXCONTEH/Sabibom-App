/** Stable platform permission codes — never scatter raw strings in UI. */
export const PLATFORM_PERMISSIONS = [
  // Dashboard and analytics
  "view_platform_dashboard",
  "view_platform_analytics",
  "view_usage_metrics",
  "view_financial_metrics",
  // Users
  "view_users",
  "manage_users",
  "disable_user",
  "restore_user",
  "view_user_activity",
  "view_user_devices",
  // Businesses
  "view_businesses",
  "manage_businesses",
  "archive_business",
  "restore_business",
  "review_business_deletion",
  "view_business_memberships",
  "view_business_activity",
  // Support
  "view_feedback",
  "manage_feedback",
  "view_support_tickets",
  "manage_support_tickets",
  "view_bug_reports",
  "manage_bug_reports",
  // AI
  "view_ai_metrics",
  "view_ai_failures",
  "retry_ai_job",
  "manage_ai_settings",
  "view_ai_provider_health",
  // System
  "view_system_health",
  "manage_feature_flags",
  "manage_maintenance_mode",
  "manage_platform_settings",
  "manage_app_versions",
  "manage_announcements",
  "send_platform_notifications",
  // Security
  "view_security_logs",
  "manage_platform_admins",
  "suspend_platform_admin",
  "view_auth_events",
  "view_rate_limit_events",
  "view_app_check_events",
  // Data operations
  "view_backup_jobs",
  "retry_backup_job",
  "view_restore_jobs",
  "approve_restore_job",
  "view_import_jobs",
  "retry_import_job",
  "view_deletion_requests",
  "process_deletion_requests",
  // Release
  "view_release_readiness",
  "manage_beta_testers",
  "manage_release_notes",
  "manage_minimum_version",
  "manage_rollout_settings",
  // Billing foundation
  "view_subscriptions",
  "manage_subscription_plans",
  "view_billing_events",
  "issue_billing_adjustment",
] as const;

export type PlatformPermission = (typeof PLATFORM_PERMISSIONS)[number];

export const PLATFORM_ROLES = [
  "super_admin",
  "support_admin",
  "security_admin",
  "operations_admin",
  "release_admin",
  "finance_admin",
  "analyst",
  "read_only_admin",
  "custom",
] as const;

export type PlatformRole = (typeof PLATFORM_ROLES)[number];

export const PLATFORM_ADMIN_STATUSES = [
  "active",
  "disabled",
  "suspended",
  "removed",
] as const;

export type PlatformAdminStatus = (typeof PLATFORM_ADMIN_STATUSES)[number];

const ALL = [...PLATFORM_PERMISSIONS] as PlatformPermission[];

const SUPPORT_DEFAULTS: PlatformPermission[] = [
  "view_platform_dashboard",
  "view_users",
  "view_user_activity",
  "view_businesses",
  "view_business_memberships",
  "view_business_activity",
  "view_feedback",
  "manage_feedback",
  "view_support_tickets",
  "manage_support_tickets",
  "view_bug_reports",
  "manage_bug_reports",
];

const SECURITY_DEFAULTS: PlatformPermission[] = [
  "view_platform_dashboard",
  "view_users",
  "disable_user",
  "restore_user",
  "view_user_activity",
  "view_user_devices",
  "view_security_logs",
  "manage_platform_admins",
  "suspend_platform_admin",
  "view_auth_events",
  "view_rate_limit_events",
  "view_app_check_events",
  "view_deletion_requests",
];

const OPERATIONS_DEFAULTS: PlatformPermission[] = [
  "view_platform_dashboard",
  "view_businesses",
  "manage_businesses",
  "archive_business",
  "restore_business",
  "view_business_activity",
  "view_backup_jobs",
  "retry_backup_job",
  "view_restore_jobs",
  "approve_restore_job",
  "view_import_jobs",
  "retry_import_job",
  "view_deletion_requests",
  "send_platform_notifications",
  "view_system_health",
];

const RELEASE_DEFAULTS: PlatformPermission[] = [
  "view_platform_dashboard",
  "manage_feature_flags",
  "manage_maintenance_mode",
  "manage_app_versions",
  "manage_announcements",
  "view_release_readiness",
  "manage_beta_testers",
  "manage_release_notes",
  "manage_minimum_version",
  "manage_rollout_settings",
];

const FINANCE_DEFAULTS: PlatformPermission[] = [
  "view_platform_dashboard",
  "view_financial_metrics",
  "view_subscriptions",
  "manage_subscription_plans",
  "view_billing_events",
  "issue_billing_adjustment",
];

const ANALYST_DEFAULTS: PlatformPermission[] = [
  "view_platform_dashboard",
  "view_platform_analytics",
  "view_usage_metrics",
  "view_ai_metrics",
  "view_system_health",
  "view_release_readiness",
];

const READ_ONLY_DEFAULTS: PlatformPermission[] = [
  "view_platform_dashboard",
  "view_platform_analytics",
  "view_usage_metrics",
  "view_users",
  "view_businesses",
  "view_feedback",
  "view_support_tickets",
  "view_bug_reports",
  "view_ai_metrics",
  "view_system_health",
  "view_security_logs",
  "view_backup_jobs",
  "view_restore_jobs",
  "view_import_jobs",
  "view_deletion_requests",
  "view_release_readiness",
  "view_subscriptions",
];

/** Default permission sets per platform role. */
export const ROLE_DEFAULT_PERMISSIONS: Record<
  Exclude<PlatformRole, "custom">,
  readonly PlatformPermission[]
> = {
  super_admin: ALL,
  support_admin: SUPPORT_DEFAULTS,
  security_admin: SECURITY_DEFAULTS,
  operations_admin: OPERATIONS_DEFAULTS,
  release_admin: RELEASE_DEFAULTS,
  finance_admin: FINANCE_DEFAULTS,
  analyst: ANALYST_DEFAULTS,
  read_only_admin: READ_ONLY_DEFAULTS,
};

export function isPlatformPermission(value: string): value is PlatformPermission {
  return (PLATFORM_PERMISSIONS as readonly string[]).includes(value);
}

export function permissionsForRole(
  role: PlatformRole,
  customPermissions: readonly string[] = [],
): PlatformPermission[] {
  if (role === "super_admin") {
    return [...ALL];
  }
  if (role === "custom") {
    return customPermissions.filter(isPlatformPermission);
  }
  const defaults = ROLE_DEFAULT_PERMISSIONS[role] ?? [];
  const extras = customPermissions.filter(isPlatformPermission);
  return Array.from(new Set<PlatformPermission>([...defaults, ...extras]));
}

export function adminHasPermission(
  role: PlatformRole,
  storedPermissions: readonly string[],
  required: PlatformPermission,
): boolean {
  if (role === "super_admin") return true;
  const effective = permissionsForRole(role, storedPermissions);
  return effective.includes(required);
}
