import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { adminFirestore } from "@/lib/firebase/admin";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS, SETTINGS_DOCS } from "@/lib/platform/collections";
import { writeAdminActivity } from "@/lib/platform-admin/repository";

export const platformGeneralSettingsSchema = z.object({
  supportEmail: z
    .string()
    .trim()
    .email()
    .max(254)
    .optional()
    .nullable()
    .or(z.literal("")),
  supportUrl: z.string().trim().url().max(500).optional().nullable().or(z.literal("")),
  defaultLocale: z.string().trim().min(2).max(16).default("en"),
  defaultTimezone: z.string().trim().min(1).max(64).default("Africa/Freetown"),
  platformName: z.string().trim().min(1).max(120).default("SabiBom"),
  statusBanner: z.string().trim().max(500).optional().nullable(),
});

export type PlatformGeneralSettings = {
  supportEmail: string | null;
  supportUrl: string | null;
  defaultLocale: string;
  defaultTimezone: string;
  platformName: string;
  statusBanner: string | null;
  updatedAt: Date | null;
  updatedBy: string | null;
};

export async function getPlatformGeneralSettings(): Promise<PlatformGeneralSettings> {
  const snap = await adminFirestore()
    .collection(COLLECTIONS.platformSettings)
    .doc(SETTINGS_DOCS.general)
    .get();
  const data = snap.exists ? snap.data() ?? {} : {};
  return {
    supportEmail:
      typeof data.supportEmail === "string" ? data.supportEmail : null,
    supportUrl: typeof data.supportUrl === "string" ? data.supportUrl : null,
    defaultLocale:
      typeof data.defaultLocale === "string" ? data.defaultLocale : "en",
    defaultTimezone:
      typeof data.defaultTimezone === "string"
        ? data.defaultTimezone
        : "Africa/Freetown",
    platformName:
      typeof data.platformName === "string" ? data.platformName : "SabiBom",
    statusBanner:
      typeof data.statusBanner === "string" ? data.statusBanner : null,
    updatedAt: asDate(data.updatedAt),
    updatedBy: typeof data.updatedBy === "string" ? data.updatedBy : null,
  };
}

export async function savePlatformGeneralSettings(input: {
  settings: z.infer<typeof platformGeneralSettingsSchema>;
  actorUid: string;
  actorName: string | null;
  actorRole: string;
  requestId?: string | null;
}): Promise<PlatformGeneralSettings> {
  const previous = await getPlatformGeneralSettings();
  const supportEmail = input.settings.supportEmail
    ? input.settings.supportEmail
    : null;
  const supportUrl = input.settings.supportUrl
    ? input.settings.supportUrl
    : null;

  await adminFirestore()
    .collection(COLLECTIONS.platformSettings)
    .doc(SETTINGS_DOCS.general)
    .set(
      {
        supportEmail,
        supportUrl,
        defaultLocale: input.settings.defaultLocale,
        defaultTimezone: input.settings.defaultTimezone,
        platformName: input.settings.platformName,
        statusBanner: input.settings.statusBanner ?? null,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: input.actorUid,
      },
      { merge: true },
    );

  await writeAdminActivity({
    adminUid: input.actorUid,
    adminName: input.actorName,
    adminRole: input.actorRole,
    actionType: "save_platform_settings",
    targetType: "platform_settings",
    targetId: SETTINGS_DOCS.general,
    description: "Updated platform general settings",
    previousStateSnapshot: {
      platformName: previous.platformName,
      defaultLocale: previous.defaultLocale,
    },
    newStateSnapshot: {
      platformName: input.settings.platformName,
      defaultLocale: input.settings.defaultLocale,
    },
    requestId: input.requestId ?? null,
  });

  return getPlatformGeneralSettings();
}
