import {createHash} from "node:crypto";

function normalized(parts: readonly string[]): string {
  return parts.map((part) => part.trim()).join("\u001f");
}

export function sha256Id(...parts: string[]): string {
  return createHash("sha256").update(normalized(parts), "utf8").digest("hex");
}

export function eventKey(
  source: string,
  businessId: string,
  sourceId: string,
  transition: string,
): string {
  return sha256Id("event", source, businessId, sourceId, transition);
}

export function ledgerId(eventId: string, userId: string): string {
  return sha256Id("ledger", eventId, userId);
}

export function notificationId(eventId: string, userId: string): string {
  return sha256Id("notification", eventId, userId);
}

export function activityId(eventId: string): string {
  return sha256Id("staff_activity", eventId);
}
