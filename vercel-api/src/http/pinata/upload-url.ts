import type {VercelRequest, VercelResponse} from "@vercel/node";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {
  MAX_UPLOAD_BYTES,
  pinataUploadRequestSchema,
} from "../../schemas/pinata-upload-schema";
import {requireBusinessAccess, requireActiveMembership} from "../../services/business-access-service";
import {pinBusinessLogo} from "../../services/pinata-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = pinataUploadRequestSchema.safeParse(readJsonBody(req));
  if (!parsed.success) {
    throw errors.invalidArgument(
      "The selected image could not be uploaded. Please try another file.",
    );
  }

  const {businessId, fileName, mimeType, fileSize, purpose, fileBase64} =
    parsed.data;
  if (purpose === "feedback_attachment") {
    // Any active member can attach a screenshot to feedback.
    await requireActiveMembership({
      uid: identity.uid,
      businessId,
    });
  } else {
    await requireBusinessAccess({
      uid: identity.uid,
      businessId,
      requiredPermission: "upload_business_logo",
    });
  }

  await enforceRateLimit({
    uid: identity.uid,
    businessId,
    operation: "pinata_upload_url",
    windowSeconds: 60,
    maxPerWindow: 8,
    dailyMax: 80,
  });

  let fileBytes: Buffer;
  try {
    fileBytes = Buffer.from(fileBase64, "base64");
  } catch {
    throw errors.invalidArgument(
      "The selected image could not be uploaded. Please try another file.",
    );
  }

  if (fileBytes.byteLength <= 0 || fileBytes.byteLength > MAX_UPLOAD_BYTES) {
    throw errors.payloadTooLarge();
  }
  if (Math.abs(fileBytes.byteLength - fileSize) > 1024) {
    // Allow small encoding drift; reject large mismatches.
    throw errors.invalidArgument(
      "The selected image could not be uploaded. Please try another file.",
    );
  }

  const pinned = await pinBusinessLogo({
    fileName,
    mimeType,
    fileBytes,
    businessId,
    uid: identity.uid,
    purpose,
  });

  sendSuccess(res, {
    cid: pinned.cid,
    logoUrl: pinned.logoUrl,
    gatewayBaseUrl: pinned.logoUrl.replace(/\/ipfs\/.*$/, ""),
    fileName: pinned.fileName,
    mimeType: pinned.mimeType,
    purpose,
  });
});
