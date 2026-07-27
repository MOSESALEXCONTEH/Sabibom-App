export function sanitizeFileName(raw: string): string {
  const base = raw.trim().replace(/[^a-zA-Z0-9._-]/g, "_");
  if (!base || base === "." || base === "..") {
    return `logo_${Date.now()}.jpg`;
  }
  return base.slice(0, 120);
}

export function extractJsonObject(content: string): unknown {
  const trimmed = content.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(trimmed.slice(start, end + 1));
    }
    throw new Error("invalid_json");
  }
}
