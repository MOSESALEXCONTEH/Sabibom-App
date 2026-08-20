import {getFirestore} from "firebase-admin/firestore";
import {
  DocumentData,
  effectiveMembership,
  EffectiveMembership,
} from "./permissions";

export interface BusinessAudience {
  ownerId?: string;
  businessName: string;
  members: EffectiveMembership[];
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

export async function loadBusinessAudience(businessId: string): Promise<BusinessAudience> {
  const db = getFirestore();
  const businessRef = db.collection("businesses").doc(businessId);
  const [business, members, roles] = await Promise.all([
    businessRef.get(),
    businessRef.collection("members").get(),
    businessRef.collection("roles").get(),
  ]);
  const ownerId = text(business.data()?.ownerId);
  const roleMap = new Map<string, DocumentData>(
    roles.docs.map((role) => [role.id, role.data()]),
  );
  const resolved = members.docs.map((member) => {
    const data = member.data();
    const roleId = text(data.roleId) ?? text(data.role) ?? "cashier";
    return effectiveMembership({
      userId: member.id,
      ownerId,
      member: data,
      role: roleMap.get(roleId),
    });
  });
  if (ownerId && !resolved.some((member) => member.userId === ownerId)) {
    resolved.push(effectiveMembership({
      userId: ownerId,
      ownerId,
      member: {status: "active", roleId: "owner", isOwner: true},
    }));
  }
  return {
    ownerId,
    businessName: text(business.data()?.name) ?? "Business",
    members: resolved,
  };
}

export function asString(value: unknown): string | undefined {
  return text(value);
}

export function asStrings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map(text).filter((item): item is string => item !== undefined);
}

export function sameStrings(left: unknown, right: unknown): boolean {
  const a = [...new Set(asStrings(left))].sort();
  const b = [...new Set(asStrings(right))].sort();
  return a.length === b.length && a.every((item, index) => item === b[index]);
}
