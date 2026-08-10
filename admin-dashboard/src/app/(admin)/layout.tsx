import { redirect } from "next/navigation";
import { AdminShell } from "@/components/layout/admin-shell";
import { AdminHttpError } from "@/lib/auth/errors";
import { requirePlatformAdmin } from "@/lib/auth/session";

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  try {
    const ctx = await requirePlatformAdmin();
    return (
      <AdminShell admin={ctx.admin} permissions={ctx.permissions}>
        {children}
      </AdminShell>
    );
  } catch (error) {
    if (error instanceof AdminHttpError) {
      if (error.code === "unauthenticated") {
        redirect("/session-expired");
      }
      if (
        error.code === "not_platform_admin" ||
        error.code === "admin_disabled"
      ) {
        redirect("/unauthorized");
      }
    }
    redirect("/login");
  }
}
