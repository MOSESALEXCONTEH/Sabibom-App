import { requirePlatformPermission } from "@/lib/auth/session";
import {
  listSecurityEvents,
  toPublicSecurityEvent,
} from "@/lib/security/repository";
import { PageHeader } from "@/components/ui/page-header";
import { SecurityEventsTable } from "@/components/security/security-events-table";

export default async function AppCheckEventsPage() {
  await requirePlatformPermission("view_app_check_events");
  const page = await listSecurityEvents({ limit: 50, category: "app_check" });
  const rows = page.items.map(toPublicSecurityEvent);

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        eyebrow="Security"
        title="App Check events"
        description="Filtered security events with category=app_check."
      />
      <SecurityEventsTable rows={rows} emptyTitle="No App Check events" />
    </div>
  );
}
