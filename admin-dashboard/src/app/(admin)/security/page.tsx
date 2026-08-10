import Link from "next/link";
import { requirePlatformPermission } from "@/lib/auth/session";
import {
  listSecurityEvents,
  toPublicSecurityEvent,
} from "@/lib/security/repository";
import { PageHeader } from "@/components/ui/page-header";
import { SecurityEventsTable } from "@/components/security/security-events-table";

export default async function SecurityPage() {
  await requirePlatformPermission("view_security_logs");
  const page = await listSecurityEvents({ limit: 50 });
  const rows = page.items.map(toPublicSecurityEvent);

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        eyebrow="Security"
        title="Security logs"
        description="IP addresses are hashed. Tokens are never returned."
        actions={
          <div className="flex flex-wrap gap-2 text-sm">
            <Link className="text-brand hover:underline" href="/security/auth-events">
              Auth events
            </Link>
            <Link className="text-brand hover:underline" href="/security/app-check">
              App Check
            </Link>
            <Link className="text-brand hover:underline" href="/security/rate-limits">
              Rate limits
            </Link>
            <Link className="text-brand hover:underline" href="/security/admin-activity">
              Admin activity
            </Link>
          </div>
        }
      />
      <SecurityEventsTable rows={rows} />
    </div>
  );
}
