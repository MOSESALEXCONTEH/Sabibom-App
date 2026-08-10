import { requirePlatformPermission } from "@/lib/auth/session";
import {
  listBetaTesters,
  toPublicBetaTester,
} from "@/lib/beta/repository";
import { PageHeader } from "@/components/ui/page-header";
import { DataTable } from "@/components/ui/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { ActionButton } from "@/components/ui/action-button";
import { BetaTesterForm } from "@/components/beta/beta-tester-form";
import { formatDate } from "@/lib/utils/serialize";

export default async function BetaTestersPage() {
  await requirePlatformPermission("manage_beta_testers");
  const page = await listBetaTesters({ limit: 50 });
  const rows = page.items.map(toPublicBetaTester);

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        eyebrow="Release"
        title="Beta testers"
        description="Invite and manage platform beta testers. Emails are masked in list views."
      />
      <BetaTesterForm />
      <DataTable
        rowKey={(row) => row.id}
        emptyTitle="No beta testers yet"
        emptyDescription="Invite the first tester using the form above."
        rows={rows}
        columns={[
          {
            key: "email",
            header: "Email",
            cell: (row) => row.email ?? "—",
          },
          {
            key: "name",
            header: "Name",
            cell: (row) => row.displayName ?? "—",
          },
          {
            key: "platform",
            header: "Platform",
            cell: (row) => row.platform,
          },
          {
            key: "status",
            header: "Status",
            cell: (row) => <StatusBadge value={row.status} />,
          },
          {
            key: "created",
            header: "Invited",
            cell: (row) => formatDate(row.createdAt),
          },
          {
            key: "actions",
            header: "Actions",
            cell: (row) => (
              <div className="flex flex-wrap gap-2">
                {row.status !== "active" ? (
                  <ActionButton
                    label="Activate"
                    method="PATCH"
                    href={`/api/admin/beta-testers/${row.id}`}
                    body={{ status: "active" }}
                    confirm="Activate this beta tester?"
                  />
                ) : null}
                {row.status !== "revoked" ? (
                  <ActionButton
                    label="Revoke"
                    method="PATCH"
                    href={`/api/admin/beta-testers/${row.id}`}
                    body={{ status: "revoked" }}
                    variant="danger"
                    confirm="Revoke beta access for this tester?"
                  />
                ) : null}
              </div>
            ),
          },
        ]}
      />
    </div>
  );
}
