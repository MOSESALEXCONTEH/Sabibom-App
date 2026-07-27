import {getEnv} from "../config/env";
import {errors} from "../utils/api-errors";
import {sanitizeFileName} from "../utils/normalize";

type PinataPinResponse = {
  IpfsHash?: string;
  cid?: string;
  data?: {cid?: string; IpfsHash?: string};
};

/**
 * Server-side Pinata upload via classic pinFileToIPFS.
 * Signed upload URLs require org:files:write; many JWTs only have pinning scope.
 */
export async function pinBusinessLogo(options: {
  fileName: string;
  mimeType: string;
  fileBytes: Buffer;
  businessId: string;
  uid: string;
  purpose: string;
}): Promise<{
  cid: string;
  logoUrl: string;
  fileName: string;
  mimeType: string;
}> {
  const env = getEnv();
  const safeName = sanitizeFileName(options.fileName);

  if (options.fileBytes.byteLength <= 0) {
    throw errors.invalidArgument(
      "The selected image could not be uploaded. Please try another file.",
    );
  }

  const form = new FormData();
  const blob = new Blob([new Uint8Array(options.fileBytes)], {
    type: options.mimeType,
  });
  form.append("file", blob, safeName);
  form.append(
    "pinataMetadata",
    JSON.stringify({
      name: safeName,
      keyvalues: {
        app: "sabibom",
        businessId: options.businessId,
        userId: options.uid,
        purpose: options.purpose,
      },
    }),
  );
  form.append(
    "pinataOptions",
    JSON.stringify({
      cidVersion: 1,
    }),
  );

  const response = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.pinataJwt}`,
    },
    body: form,
  });

  if (!response.ok) {
    const detail = (await response.text()).slice(0, 300);
    console.error("[sabibom-api] pinata pin failed", {
      status: response.status,
      detail,
    });
    throw errors.unavailable(
      "The image could not be uploaded. Your previous business image has not been changed.",
    );
  }

  const body = (await response.json()) as PinataPinResponse;
  const cid = body.IpfsHash || body.cid || body.data?.cid || body.data?.IpfsHash;
  if (!cid) {
    throw errors.unavailable(
      "The image could not be uploaded. Your previous business image has not been changed.",
    );
  }

  const gateway = env.pinataGateway.replace(/\/$/, "").replace(/\/ipfs$/i, "");
  return {
    cid,
    logoUrl: `${gateway}/ipfs/${cid}`,
    fileName: safeName,
    mimeType: options.mimeType,
  };
}

/** @deprecated Prefer pinBusinessLogo — kept for type compatibility during migration. */
export async function createPinataSignedUploadUrl(options: {
  fileName: string;
  mimeType: string;
  fileSize: number;
  businessId: string;
  uid: string;
  purpose: string;
}): Promise<{
  uploadUrl: string;
  expiresIn: number;
  gatewayBaseUrl: string;
  fileName: string;
}> {
  void options;
  throw errors.unavailable(
    "Logo upload was upgraded. Please update the app and try again.",
  );
}
