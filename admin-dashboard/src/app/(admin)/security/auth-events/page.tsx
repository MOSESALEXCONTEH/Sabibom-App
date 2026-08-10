import { requirePlatformPermission } from "@/lib/auth/session";
import {
  listSecurityEvents,
  toPublicSecurityEvent,
} from "@/lib/security/repository";
import { PageHeader } from "@/components/ui/page-header";
import { SecurityEventsTable } from "@/components/security/security-events-table";

export default async function AuthEventsPage() {
  await requirePlatformPermission("view_auth_events");
  const page = await listSecurityEvents({ limit: 50, category: "auth" });
  const rows = page.items.map(toPublicSecurityEvent);

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        eyebrow="Security"
        title="Authentication events"
        description="Filtered security events with category=auth. IPs hashed; tokens redacted."
      />
      <SecurityEventsTable rows={rows} emptyTitle="No auth events" />
    </div>
  );
}
