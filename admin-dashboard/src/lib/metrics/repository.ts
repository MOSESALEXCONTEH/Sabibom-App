import { FieldValue } from "firebase-admin/firestore";
import { adminAuth, adminFirestore } from "@/lib/firebase/admin";
import { asDate } from "@/lib/firestore/dates";
import { COLLECTIONS, SETTINGS_DOCS } from "@/lib/platform/collections";

export type DailyMetric = {
  dateKey: string;
  registeredUsers: number;
  activeUsers: number;
  newUsers: number;
  totalBusinesses: number;
  newBusinesses: number;
  activeBusinesses: number;
  salesCount: number;
  salesValueMinor: number;
  sabiRequestCount: number;
  sabiFailureCount: number;
  supportTicketCount: number;
  feedbackCount: number;
  backupJobCount: number;
  backupFailureCount: number;
  importJobCount: number;
  importFailureCount: number;
  notificationCount: number;
  pushFailureCount: number;
  updatedAt: Date | null;
};

export type DashboardOverview = {
  totalUsers: number;
  activeUsers: number;
  totalBusinesses: number;
  activeBusinesses: number;
  newUsersThisWeek: number;
  newBusinessesThisWeek: number;
  completedSalesToday: number;
  sabiRequestsToday: number;
  aiFailureRate: number;
  openSupportTickets: number;
  openBugReports: number;
  failedBackupJobs: number;
  failedImportJobs: number;
  pendingDeletionRequests: number;
  currentProductionVersion: string | null;
  maintenanceEnabled: boolean;
  series: DailyMetric[];
};

function dateKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function mapDaily(id: string, data: FirebaseFirestore.DocumentData): DailyMetric {
  return {
    dateKey: typeof data.dateKey === "string" ? data.dateKey : id,
    registeredUsers: Number(data.registeredUsers ?? 0),
    activeUsers: Number(data.activeUsers ?? 0),
    newUsers: Number(data.newUsers ?? 0),
    totalBusinesses: Number(data.totalBusinesses ?? 0),
    newBusinesses: Number(data.newBusinesses ?? 0),
    activeBusinesses: Number(data.activeBusinesses ?? 0),
    salesCount: Number(data.salesCount ?? 0),
    salesValueMinor: Number(data.salesValueMinor ?? 0),
    sabiRequestCount: Number(data.sabiRequestCount ?? 0),
    sabiFailureCount: Number(data.sabiFailureCount ?? 0),
    supportTicketCount: Number(data.supportTicketCount ?? 0),
    feedbackCount: Number(data.feedbackCount ?? 0),
    backupJobCount: Number(data.backupJobCount ?? 0),
    backupFailureCount: Number(data.backupFailureCount ?? 0),
    importJobCount: Number(data.importJobCount ?? 0),
    importFailureCount: Number(data.importFailureCount ?? 0),
    notificationCount: Number(data.notificationCount ?? 0),
    pushFailureCount: Number(data.pushFailureCount ?? 0),
    updatedAt: asDate(data.updatedAt),
  };
}

async function safeCount(
  collection: string,
  where?: { field: string; op: FirebaseFirestore.WhereFilterOp; value: unknown },
): Promise<number> {
  try {
    let q: FirebaseFirestore.Query = adminFirestore().collection(collection);
    if (where) q = q.where(where.field, where.op, where.value);
    const agg = await q.count().get();
    return agg.data().count;
  } catch {
    try {
      let q: FirebaseFirestore.Query = adminFirestore().collection(collection);
      if (where) q = q.where(where.field, where.op, where.value);
      const snap = await q.limit(500).get();
      return snap.size;
    } catch {
      return 0;
    }
  }
}

async function safeCountIn(
  collection: string,
  field: string,
  values: string[],
): Promise<number> {
  const counts = await Promise.all(
    values.map((value) =>
      safeCount(collection, { field, op: "==", value }),
    ),
  );
  return counts.reduce((sum, n) => sum + n, 0);
}

export async function listDailyMetrics(days = 14): Promise<DailyMetric[]> {
  const snap = await adminFirestore()
    .collection(COLLECTIONS.platformMetricsDaily)
    .orderBy("dateKey", "desc")
    .limit(days)
    .get()
    .catch(async () =>
      adminFirestore()
        .collection(COLLECTIONS.platformMetricsDaily)
        .limit(days)
        .get(),
    );
  return snap.docs
    .map((doc) => mapDaily(doc.id, doc.data() ?? {}))
    .sort((a, b) => a.dateKey.localeCompare(b.dateKey));
}

export async function getDashboardOverview(): Promise<DashboardOverview> {
  const today = dateKey(new Date());
  const weekAgo = new Date();
  weekAgo.setDate(weekAgo.getDate() - 7);

  const [
    authUsers,
    totalBusinesses,
    activeBusinesses,
    openSupportTickets,
    openBugReports,
    failedBackupJobs,
    failedImportJobs,
    pendingDeletionRequests,
    series,
    publicSettings,
    productionVersion,
  ] = await Promise.all([
    adminAuth()
      .listUsers(1000)
      .then((r) => r.users)
      .catch(() => [] as Awaited<ReturnType<ReturnType<typeof adminAuth>["listUsers"]>>["users"]),
    safeCount(COLLECTIONS.businesses),
    safeCount(COLLECTIONS.businesses, {
      field: "status",
      op: "==",
      value: "active",
    }),
    safeCountIn(COLLECTIONS.supportTickets, "status", [
      "new",
      "open",
      "waiting_for_user",
      "waiting_for_admin",
    ]),
    safeCountIn(COLLECTIONS.bugReports, "status", [
      "new",
      "confirmed",
      "in_progress",
      "ready_for_retest",
    ]),
    safeCount(COLLECTIONS.backupJobs, {
      field: "status",
      op: "==",
      value: "failed",
    }),
    safeCount(COLLECTIONS.importJobs, {
      field: "status",
      op: "==",
      value: "failed",
    }),
    safeCount(COLLECTIONS.deletionRequests, {
      field: "status",
      op: "==",
      value: "pending",
    }),
    listDailyMetrics(14),
    adminFirestore()
      .collection(COLLECTIONS.platformSettings)
      .doc(SETTINGS_DOCS.public)
      .get()
      .catch(() => null),
    adminFirestore()
      .collection(COLLECTIONS.platformAppVersions)
      .where("status", "==", "production")
      .limit(1)
      .get()
      .catch(() => null),
  ]);

  const todayMetric = series.find((m) => m.dateKey === today);
  const newUsersThisWeek = authUsers.filter((u) => {
    if (!u.metadata.creationTime) return false;
    return new Date(u.metadata.creationTime) >= weekAgo;
  }).length;

  const newBusinessesThisWeek = series
    .filter((m) => m.dateKey >= dateKey(weekAgo))
    .reduce((sum, m) => sum + m.newBusinesses, 0);

  const sabiRequestsToday = todayMetric?.sabiRequestCount ?? 0;
  const sabiFailuresToday = todayMetric?.sabiFailureCount ?? 0;
  const aiFailureRate =
    sabiRequestsToday > 0 ? sabiFailuresToday / sabiRequestsToday : 0;

  const publicData = publicSettings?.data() ?? {};
  const prodDoc = productionVersion?.docs?.[0]?.data() ?? null;

  return {
    totalUsers: authUsers.length,
    activeUsers: authUsers.filter((u) => !u.disabled).length,
    totalBusinesses,
    activeBusinesses,
    newUsersThisWeek,
    newBusinessesThisWeek,
    completedSalesToday: todayMetric?.salesCount ?? 0,
    sabiRequestsToday,
    aiFailureRate,
    openSupportTickets,
    openBugReports,
    failedBackupJobs,
    failedImportJobs,
    pendingDeletionRequests,
    currentProductionVersion:
      prodDoc && typeof prodDoc.versionName === "string"
        ? prodDoc.versionName
        : null,
    maintenanceEnabled: publicData.maintenanceEnabled === true,
    series,
  };
}

/** Upsert a daily metrics doc (used by jobs / tests; never from browser). */
export async function upsertDailyMetric(
  dateKeyValue: string,
  patch: Partial<DailyMetric>,
): Promise<void> {
  await adminFirestore()
    .collection(COLLECTIONS.platformMetricsDaily)
    .doc(dateKeyValue)
    .set(
      {
        dateKey: dateKeyValue,
        ...patch,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}
