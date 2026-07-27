import {describe, expect, it} from "vitest";
import {pinataUploadRequestSchema} from "../src/schemas/pinata-upload-schema";
import {sanitizeFileName} from "../src/utils/normalize";

describe("pinata upload validation", () => {
  it("rejects unsupported mime types", () => {
    expect(() =>
      pinataUploadRequestSchema.parse({
        businessId: "biz-1",
        fileName: "logo.gif",
        mimeType: "image/gif",
        fileSize: 1000,
        purpose: "business_logo",
        fileBase64: "aaaa",
      }),
    ).toThrow();
  });

  it("rejects oversized files", () => {
    expect(() =>
      pinataUploadRequestSchema.parse({
        businessId: "biz-1",
        fileName: "logo.jpg",
        mimeType: "image/jpeg",
        fileSize: 5 * 1024 * 1024,
        purpose: "business_logo",
        fileBase64: "a".repeat(100),
      }),
    ).toThrow();
  });

  it("accepts valid logo payload", () => {
    const parsed = pinataUploadRequestSchema.parse({
      businessId: "biz-1",
      fileName: "logo.jpg",
      mimeType: "image/jpeg",
      fileSize: 1200,
      purpose: "business_logo",
      fileBase64: Buffer.from("fake-image").toString("base64"),
    });
    expect(parsed.fileName).toBe("logo.jpg");
  });

  it("accepts feedback_attachment purpose", () => {
    const parsed = pinataUploadRequestSchema.parse({
      businessId: "biz-1",
      fileName: "bug.png",
      mimeType: "image/png",
      fileSize: 800,
      purpose: "feedback_attachment",
      fileBase64: Buffer.from("fake-image").toString("base64"),
    });
    expect(parsed.purpose).toBe("feedback_attachment");
  });

  it("sanitizes unsafe file names", () => {
    expect(sanitizeFileName("../../evil name!.png")).toBe(".._.._evil_name_.png");
  });
});
