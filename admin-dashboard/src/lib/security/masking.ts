import { hashIdentifier, maskToken, maskUid } from "@/lib/utils/mask";

const TOKEN_KEYS = new Set([
  "token",
  "idtoken",
  "id_token",
  "accesstoken",
  "access_token",
  "refreshtoken",
  "refresh_token",
  "sessioncookie",
  "session_cookie",
  "authorization",
  "apikey",
  "api_key",
  "secret",
  "password",
]);

const IP_KEYS = new Set([
  "ip",
  "ipaddress",
  "ip_address",
  "clientip",
  "client_ip",
  "remoteip",
  "remote_ip",
  "xforwardedfor",
  "x_forwarded_for",
]);

function normalizeKey(key: string): string {
  return key.toLowerCase().replace(/[^a-z0-9_]/g, "");
}

/** Hash IPs; never return raw tokens in admin security views. */
export function maskSecurityValue(key: string, value: unknown): unknown {
  const nk = normalizeKey(key);
  if (value == null) return value;

  if (IP_KEYS.has(nk) || nk.endsWith("ip") || nk.includes("ipaddress")) {
    if (typeof value === "string" && value.trim()) {
      return hashIdentifier(value.trim());
    }
    return value;
  }

  if (TOKEN_KEYS.has(nk) || nk.includes("token") || nk.includes("secret")) {
    if (typeof value === "string") return maskToken(value);
    return "[redacted]";
  }

  if (nk === "uid" || nk === "userid" || nk === "actoruid" || nk === "adminuid") {
    if (typeof value === "string") return maskUid(value);
  }

  return value;
}

export function maskSecurityMetadata(
  metadata: Record<string, unknown> | null | undefined,
): Record<string, unknown> | null {
  if (!metadata || typeof metadata !== "object") return null;
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(metadata)) {
    if (value && typeof value === "object" && !Array.isArray(value)) {
      out[key] = maskSecurityMetadata(value as Record<string, unknown>);
    } else if (Array.isArray(value)) {
      out[key] = value.map((item, index) =>
        typeof item === "object" && item
          ? maskSecurityMetadata(item as Record<string, unknown>)
          : maskSecurityValue(String(index), item),
      );
    } else {
      out[key] = maskSecurityValue(key, value);
    }
  }
  return out;
}

export function maskIp(ip: string | null | undefined): string | null {
  if (!ip) return null;
  return hashIdentifier(ip.trim());
}
