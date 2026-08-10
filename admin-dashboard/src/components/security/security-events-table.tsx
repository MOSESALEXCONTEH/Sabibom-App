import { DataTable } from "@/components/ui/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import type { PublicSecurityEvent } from "@/lib/security/repository";
import { formatDate } from "@/lib/utils/serialize";

export function SecurityEventsTable({
  rows,
  emptyTitle,
}: {
  rows: PublicSecurityEvent[];
  emptyTitle?: string;
}) {
  return (
    <DataTable
      rowKey={(row) => row.id}
      rows={rows}
      emptyTitle={emptyTitle ?? "No security events"}
      emptyDescription="Events appear when writers emit to platform_security_events."
      columns={[
        {
          key: "created",
          header: "When",
          cell: (row) => formatDate(row.createdAt),
        },
        {
          key: "category",
          header: "Category",
          cell: (row) => <StatusBadge value={row.category} />,
        },
        {
          key: "type",
          header: "Event",
          cell: (row) => row.eventType,
        },
        {
          key: "severity",
          header: "Severity",
          cell: (row) => <StatusBadge value={row.severity} />,
        },
        {
          key: "actor",
          header: "Actor",
          cell: (row) => row.actorUid ?? "—",
        },
        {
          key: "ip",
          header: "IP (hashed)",
          cell: (row) => row.ipHash ?? "—",
        },
        {
          key: "message",
          header: "Message",
          cell: (row) => row.message ?? "—",
        },
      ]}
    />
  );
}
