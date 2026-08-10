import { withAdminRoute } from "@/lib/api/handler";
import {
  getPlatformGeneralSettings,
  platformGeneralSettingsSchema,
  savePlatformGeneralSettings,
} from "@/lib/settings/repository";
import { serializeDates } from "@/lib/utils/serialize";

export const GET = withAdminRoute(
  { permission: "manage_platform_settings" },
  async () => serializeDates(await getPlatformGeneralSettings()),
);

export const PATCH = withAdminRoute(
  { permission: "manage_platform_settings" },
  async ({ request, ctx, requestId }) => {
    const settings = platformGeneralSettingsSchema.parse(await request.json());
    const saved = await savePlatformGeneralSettings({
      settings,
      actorUid: ctx.uid,
      actorName: ctx.admin.displayName,
      actorRole: ctx.admin.role,
      requestId,
    });
    return serializeDates(saved);
  },
);
