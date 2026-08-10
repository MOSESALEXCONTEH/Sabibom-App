import { adminFirestore } from "@/lib/firebase/admin";
import { COLLECTIONS } from "@/lib/platform/collections";
import { maskEmail, maskPhone, maskUid } from "@/lib/utils/mask";
import {
  clampSearchLimit,
  SEARCH_PER_COLLECTION_LIMIT,
} from "@/lib/search/bounds";

export type SearchHit = {
  id: string;
  label: string;
  subtitle?: string | null;
  href: string;
  meta?: Record<string, string | null>;
};

export type GlobalSearchResult = {
  q: string;
  limit: number;
  users: SearchHit[];
  businesses: SearchHit[];
  feedback: SearchHit[];
  tickets: SearchHit[];
  bugs: SearchHit[];
  versions: SearchHit[];
};

function includesQuery(haystack: unknown, q: string): boolean {
  if (typeof haystack !== "string") return false;
  return haystack.toLowerCase().includes(q);
}

async function safeList(
  collection: string,
  limit: number,
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  try {
    const snap = await adminFirestore()
      .collection(collection)
      .limit(Math.min(limit * 5, 50))
      .get();
    return snap.docs;
  } catch {
    return [];
  }
}

export async function globalAdminSearch(input: {
  q: string;
  limit?: number;
}): Promise<GlobalSearchResult> {
  const q = input.q.trim().toLowerCase();
  const limit = clampSearchLimit(input.limit ?? SEARCH_PER_COLLECTION_LIMIT);

  const [
    userDocs,
    businessDocs,
    feedbackDocs,
    ticketDocs,
    bugDocs,
    versionDocs,
  ] = await Promise.all([
    safeList(COLLECTIONS.users, limit),
    safeList(COLLECTIONS.businesses, limit),
    safeList(COLLECTIONS.feedback, limit),
    safeList(COLLECTIONS.supportTickets, limit),
    safeList(COLLECTIONS.bugReports, limit),
    safeList(COLLECTIONS.platformAppVersions, limit),
  ]);

  const users: SearchHit[] = [];
  for (const doc of userDocs) {
    if (users.length >= limit) break;
    const data = doc.data() ?? {};
    const email = typeof data.email === "string" ? data.email : "";
    const fullName =
      typeof data.fullName === "string"
        ? data.fullName
        : typeof data.displayName === "string"
          ? data.displayName
          : "";
    if (
      includesQuery(doc.id, q) ||
      includesQuery(email, q) ||
      includesQuery(fullName, q)
    ) {
      users.push({
        id: doc.id,
        label: fullName || maskEmail(email) || maskUid(doc.id) || doc.id,
        subtitle: maskEmail(email),
        href: `/users/${doc.id}`,
        meta: {
          uid: maskUid(doc.id),
          phone: maskPhone(
            typeof data.phoneNumber === "string" ? data.phoneNumber : null,
          ),
        },
      });
    }
  }

  const businesses: SearchHit[] = [];
  for (const doc of businessDocs) {
    if (businesses.length >= limit) break;
    const data = doc.data() ?? {};
    const name = typeof data.name === "string" ? data.name : doc.id;
    const email = typeof data.email === "string" ? data.email : "";
    if (
      includesQuery(doc.id, q) ||
      includesQuery(name, q) ||
      includesQuery(email, q)
    ) {
      businesses.push({
        id: doc.id,
        label: name,
        subtitle: maskEmail(email),
        href: `/businesses/${doc.id}`,
        meta: {
          status: typeof data.status === "string" ? data.status : null,
        },
      });
    }
  }

  const feedback: SearchHit[] = [];
  for (const doc of feedbackDocs) {
    if (feedback.length >= limit) break;
    const data = doc.data() ?? {};
    const title = typeof data.title === "string" ? data.title : doc.id;
    const description =
      typeof data.description === "string" ? data.description : "";
    if (
      includesQuery(doc.id, q) ||
      includesQuery(title, q) ||
      includesQuery(description, q)
    ) {
      feedback.push({
        id: doc.id,
        label: title,
        subtitle:
          typeof data.status === "string" ? data.status : null,
        href: `/feedback/${doc.id}`,
      });
    }
  }

  const tickets: SearchHit[] = [];
  for (const doc of ticketDocs) {
    if (tickets.length >= limit) break;
    const data = doc.data() ?? {};
    const subject =
      typeof data.subject === "string"
        ? data.subject
        : typeof data.title === "string"
          ? data.title
          : doc.id;
    if (
      includesQuery(doc.id, q) ||
      includesQuery(subject, q) ||
      includesQuery(data.description, q)
    ) {
      tickets.push({
        id: doc.id,
        label: subject,
        subtitle:
          typeof data.status === "string" ? data.status : null,
        href: `/support/${doc.id}`,
      });
    }
  }

  const bugs: SearchHit[] = [];
  for (const doc of bugDocs) {
    if (bugs.length >= limit) break;
    const data = doc.data() ?? {};
    const title =
      typeof data.title === "string"
        ? data.title
        : typeof data.summary === "string"
          ? data.summary
          : doc.id;
    const severity =
      typeof data.severity === "string"
        ? data.severity
        : typeof data.priority === "string"
          ? data.priority
          : null;
    if (
      includesQuery(doc.id, q) ||
      includesQuery(title, q) ||
      includesQuery(severity, q)
    ) {
      bugs.push({
        id: doc.id,
        label: title,
        subtitle: severity,
        href: `/bugs/${doc.id}`,
      });
    }
  }

  const versions: SearchHit[] = [];
  for (const doc of versionDocs) {
    if (versions.length >= limit) break;
    const data = doc.data() ?? {};
    const version =
      typeof data.version === "string"
        ? data.version
        : typeof data.label === "string"
          ? data.label
          : doc.id;
    const platform =
      typeof data.platform === "string" ? data.platform : null;
    if (
      includesQuery(doc.id, q) ||
      includesQuery(version, q) ||
      includesQuery(platform, q)
    ) {
      versions.push({
        id: doc.id,
        label: version,
        subtitle: platform,
        href: `/releases`,
      });
    }
  }

  return { q: input.q.trim(), limit, users, businesses, feedback, tickets, bugs, versions };
}
