const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_UPLOAD_BYTES = 2 * 1024 * 1024;

export function sanitizeFileName(raw: string): string {
  const base = raw.trim().replace(/[^a-zA-Z0-9._-]/g, "_");
  if (!base || base === "." || base === "..") {
    return `logo_${Date.now()}.jpg`;
  }
  return base.slice(0, 120);
}

export function assertAllowedImage(mimeType: string, fileSize: number): void {
  if (!ALLOWED_MIME.has(mimeType)) {
    throw new Error("Unsupported image format. Use JPEG, PNG or WebP.");
  }
  if (!Number.isFinite(fileSize) || fileSize <= 0) {
    throw new Error("Invalid file size.");
  }
  if (fileSize > MAX_UPLOAD_BYTES) {
    throw new Error("Image is too large. Maximum size is 2 MB after compression.");
  }
}

export const maxUploadBytes = MAX_UPLOAD_BYTES;
export const allowedMimeTypes = [...ALLOWED_MIME];
