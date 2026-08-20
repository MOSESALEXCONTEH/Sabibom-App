"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveNotificationPolicy = resolveNotificationPolicy;
exports.isQuietHours = isQuietHours;
exports.channelDecision = channelDecision;
function resolveNotificationPolicy(businessPreferences, legacyPreferences, category) {
    const data = businessPreferences ?? legacyPreferences ?? {};
    const categoryValue = category === "approval" ? data.approvalEnabled :
        (data.staffActivityEnabled ?? data.team);
    return {
        inAppEnabled: data.inAppEnabled !== false,
        pushEnabled: data.pushEnabled !== false,
        categoryEnabled: categoryValue !== false,
        quietHoursEnabled: data.quietHoursEnabled === true,
        quietHoursStart: typeof data.quietHoursStart === "string" ?
            data.quietHoursStart : "22:00",
        quietHoursEnd: typeof data.quietHoursEnd === "string" ?
            data.quietHoursEnd : "07:00",
        timezone: typeof data.timezone === "string" && data.timezone.trim() ?
            data.timezone : "Africa/Freetown",
    };
}
function minuteOfDay(value) {
    const match = /^(\d{2}):(\d{2})$/.exec(value);
    if (!match)
        return undefined;
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    if (hour > 23 || minute > 59)
        return undefined;
    return hour * 60 + minute;
}
function localMinute(now, timezone) {
    try {
        const parts = new Intl.DateTimeFormat("en-GB", {
            timeZone: timezone,
            hour: "2-digit",
            minute: "2-digit",
            hourCycle: "h23",
        }).formatToParts(now);
        const hour = Number(parts.find((part) => part.type === "hour")?.value ?? 0);
        const minute = Number(parts.find((part) => part.type === "minute")?.value ?? 0);
        return hour * 60 + minute;
    }
    catch {
        return now.getUTCHours() * 60 + now.getUTCMinutes();
    }
}
function isQuietHours(policy, now) {
    if (!policy.quietHoursEnabled)
        return false;
    const start = minuteOfDay(policy.quietHoursStart);
    const end = minuteOfDay(policy.quietHoursEnd);
    if (start === undefined || end === undefined || start === end)
        return false;
    const current = localMinute(now, policy.timezone);
    return start < end ? current >= start && current < end :
        current >= start || current < end;
}
function channelDecision(policy, now) {
    const quiet = policy.categoryEnabled && policy.pushEnabled &&
        isQuietHours(policy, now);
    return {
        inApp: policy.categoryEnabled && policy.inAppEnabled,
        push: policy.categoryEnabled && policy.pushEnabled && !quiet,
        pushQuietSuppressed: quiet,
    };
}
//# sourceMappingURL=policy.js.map