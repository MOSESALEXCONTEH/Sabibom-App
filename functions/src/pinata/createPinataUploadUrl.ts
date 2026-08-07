import {onCall} from "firebase-functions/v2/https";
import {z} from "zod";
import {
  requireAuthenticatedUid,
  requireBusinessMember,
  requireOwnerOrManager,
} from "../auth/businessAuthorization";
import {invalidArgument, unavailable, internal} from "../shared/errors";
import {enforceRateLimit} from "../shared/rateLimiter";
import {pinataGateway, pinataJwt} from "../shared/secrets";
import {
  assertAllowedImage,
  sanitizeFileName,
} from "../shared/validation";

const requestSchema = z.object({
  businessId: z.string().min(1).max(128),
  fileName: z.string().min(1).max(180),
  mimeType: z.enum(["image/jpeg", "image/png", "image/webp"]),
  fileSize: z.number().int().positive().max(2 * 1024 * 1024),
});

type PinataPresignResponse = {
  data?: {
    url?: string;
    expiresAt?: string;
    key?: string;
  };
};

/**
 * Creates a short-lived Pinata upload URL. The Pinata JWT never leaves the server.
 */
export const createPinataUploadUrl = onCall(
  {
    region: "us-central1",
    secrets: [pinataJwt, pinataGateway],
    enforceAppCheck: false,
  },
  async (request) => {
    const uid = await requireAuthenticatedUid(request.auth?.uid);
    const parsed = requestSchema.safeParse(request.data);
    if (!parsed.success) {
      throw invalidArgument("Invalid upload request.");
    }

    const {businessId, fileName, mimeType, fileSize} = parsed.data;
    const membership = await requireBusinessMember(uid, businessId);
    requireOwnerOrManager(membership.role, membership.isOwner);

    try {
      assertAllowedImage(mimeType, fileSize);
    } catch (error) {
      throw invalidArgument(
        error instanceof Error ? error.message : "Invalid image upload.",
      );
    }

    await enforceRateLimit({
      uid,
      businessId,
      operation: "createPinataUploadUrl",
      windowSeconds: 60,
      maxPerWindow: 8,
      dailyMax: 80,
    });

    const jwt = pinataJwt.value();
    let gateway = pinataGateway.value().replace(/\/$/, "");
    gateway = gateway.replace(/\/ipfs$/i, "");
    if (!jwt || !gateway) {
      throw unavailable("Image upload is not configured yet.");
    }

    const safeName = sanitizeFileName(fileName);
    const expiresInSeconds = 5 * 60;
    const expiresAt = Math.floor(Date.now() / 1000) + expiresInSeconds;

    try {
      const response = await fetch(
        "https://uploads.pinata.cloud/v3/files/sign",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${jwt}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            network: "public",
            date: Math.floor(Date.now() / 1000),
            // Pinata expects a duration in seconds for signed uploads.
            expires: expiresInSeconds,
            max_file_size: fileSize,
            allow_mime_types: [mimeType, "image/*"],
            filename: safeName,
            keyvalues: {
              businessId,
              uploadedBy: uid,
              purpose: "business_logo",
            },
          }),
        },
      );

      if (!response.ok) {
        // Fallback: signed URL endpoint variants differ by Pinata plan.
        // Return a controlled upload session the client can use with multipart
        // against the standard pinFile endpoint via a short-lived custom token pattern.
        throw new Error(`pinata_sign_failed_${response.status}`);
      }

      const body = (await response.json()) as PinataPresignResponse;
      const uploadUrl = body.data?.url;
      if (!uploadUrl) {
        throw new Error("pinata_missing_url");
      }

      return {
        uploadUrl,
        expiresAt: body.data?.expiresAt ?? new Date(expiresAt * 1000).toISOString(),
        fileName: safeName,
        mimeType,
        maxBytes: fileSize,
        gatewayBaseUrl: gateway,
        purpose: "business_logo",
      };
    } catch (error) {
      // Controlled fallback: issue a one-shot server-mediated upload token stored in Firestore.
      // Flutter still never receives PINATA_JWT.
      const {getFirestore, FieldValue} = await import("firebase-admin/firestore");
      const tokenRef = getFirestore().collection("pinata_upload_sessions").doc();
      const sessionExpires = Date.now() + 5 * 60 * 1000;
      await tokenRef.set({
        businessId,
        uid,
        fileName: safeName,
        mimeType,
        fileSize,
        purpose: "business_logo",
        expiresAtMs: sessionExpires,
        createdAt: FieldValue.serverTimestamp(),
        used: false,
      });

      return {
        uploadMode: "callable_proxy" as const,
        uploadSessionId: tokenRef.id,
        expiresAt: new Date(sessionExpires).toISOString(),
        fileName: safeName,
        mimeType,
        maxBytes: fileSize,
        gatewayBaseUrl: gateway,
        purpose: "business_logo",
        note:
          error instanceof Error && error.message.startsWith("pinata_sign_failed")
            ? "presign_unavailable_using_proxy"
            : "presign_unavailable_using_proxy",
      };
    }
  },
);

/**
 * Completes a proxy upload when Pinata presign is unavailable for the account.
 * Accepts base64 image bytes only through this authenticated callable.
 */
export const uploadBusinessLogoViaProxy = onCall(
  {
    region: "us-central1",
    secrets: [pinataJwt, pinataGateway],
    enforceAppCheck: false,
    memory: "512MiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = await requireAuthenticatedUid(request.auth?.uid);
    const schema = z.object({
      businessId: z.string().min(1),
      uploadSessionId: z.string().min(1),
      base64Data: z.string().min(1).max(4_000_000),
    });
    const parsed = schema.safeParse(request.data);
    if (!parsed.success) {
      throw invalidArgument("Invalid upload payload.");
    }

    const {businessId, uploadSessionId, base64Data} = parsed.data;
    const membership = await requireBusinessMember(uid, businessId);
    requireOwnerOrManager(membership.role, membership.isOwner);

    await enforceRateLimit({
      uid,
      businessId,
      operation: "uploadBusinessLogoViaProxy",
      windowSeconds: 60,
      maxPerWindow: 5,
      dailyMax: 40,
    });

    const {getFirestore, FieldValue} = await import("firebase-admin/firestore");
    const db = getFirestore();
    const sessionRef = db.collection("pinata_upload_sessions").doc(uploadSessionId);
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
      throw invalidArgument("Upload session expired. Please try again.");
    }
    const session = sessionSnap.data()!;
    if (
      session.uid !== uid ||
      session.businessId !== businessId ||
      session.used === true ||
      (session.expiresAtMs as number) < Date.now()
    ) {
      throw invalidArgument("Upload session is no longer valid.");
    }

    const jwt = pinataJwt.value();
    let gateway = pinataGateway.value().replace(/\/$/, "");
    gateway = gateway.replace(/\/ipfs$/i, "");
    if (!jwt || !gateway) {
      throw unavailable("Image upload is not configured yet.");
    }

    const bytes = Buffer.from(base64Data, "base64");
    if (bytes.byteLength <= 0 || bytes.byteLength > (session.fileSize as number)) {
      throw invalidArgument("Uploaded image size is invalid.");
    }

    const form = new FormData();
    const blob = new Blob([bytes], {type: session.mimeType as string});
    form.append("file", blob, session.fileName as string);
    form.append(
      "pinataMetadata",
      JSON.stringify({
        name: session.fileName,
        keyvalues: {
          businessId,
          uploadedBy: uid,
          purpose: "business_logo",
        },
      }),
    );
    form.append(
      "pinataOptions",
      JSON.stringify({cidVersion: 1}),
    );

    const pinResponse = await fetch(
      "https://api.pinata.cloud/pinning/pinFileToIPFS",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${jwt}`,
        },
        body: form,
      },
    );

    if (!pinResponse.ok) {
      throw unavailable("The image could not be uploaded. Please try again.");
    }

    const pinBody = (await pinResponse.json()) as {
      IpfsHash?: string;
      cid?: string;
    };
    const cid = pinBody.IpfsHash ?? pinBody.cid;
    if (!cid) {
      throw internal();
    }

    await sessionRef.set(
      {used: true, usedAt: FieldValue.serverTimestamp(), cid},
      {merge: true},
    );

    const logoUrl = `${gateway}/ipfs/${cid}`;
    return {
      cid,
      logoUrl,
      fileName: session.fileName as string,
      mimeType: session.mimeType as string,
    };
  },
);
