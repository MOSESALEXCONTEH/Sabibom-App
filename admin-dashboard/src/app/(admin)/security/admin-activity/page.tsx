import { requirePlatformPermission } from "@/lib/auth/session";
import { listAdminActivity } from "@/lib/platform-admin/repository";
import { PageHeader } from "@/components/ui/page-header";
import { DataTable } from "@/components/ui/data-table";
import { formatDate } from "@/lib/utils/serialize";
import { maskUid } from "@/lib/utils/mask";

export default async function AdminActivityPage() {
  await requirePlatformPermission("view_security_logs");
  const page = await listAdminActivity({ limit: 50 });

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        eyebrow="Security"
        title="Admin activity"
        description="Audit trail of platform admin actions."
      />
      <DataTable
        rowKey={(row) => row.id}
        rows={page.items}
        emptyTitle="No admin activity yet"
        columns={[
          {
            key: "when",
            header: "When",
            cell: (row) => formatDate(row.createdAt),
          },
          {
            key: "admin",
            header: "Admin",
            cell: (row) =>
              row.adminName || maskUid(row.adminUid) || row.adminUid,
          },
          {
            key: "action",
            header: "Action",
            cell: (row) => row.actionType,
          },
          {
            key: "target",
            header: "Target",
            cell: (row) =>
              `${row.targetType}:${row.targetLabel || row.targetId}`,
          },
          {
            key: "description",
            header: "Description",
            cell: (row) => row.description,
          },
        ]}
      />
    </div>
  );
}
