import { requirePlatformPermission } from "@/lib/auth/session";
import {
  listSecurityEvents,
  toPublicSecurityEvent,
} from "@/lib/security/repository";
import { PageHeader } from "@/components/ui/page-header";
import { SecurityEventsTable } from "@/components/security/security-events-table";

export default async function RateLimitEventsPage() {
  await requirePlatformPermission("view_rate_limit_events");
  const page = await listSecurityEvents({ limit: 50, category: "rate_limit" });
  const rows = page.items.map(toPublicSecurityEvent);

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        eyebrow="Security"
        title="Rate limit events"
        description="Filtered security events with category=rate_limit."
      />
      <SecurityEventsTable rows={rows} emptyTitle="No rate limit events" />
    </div>
  );
}
