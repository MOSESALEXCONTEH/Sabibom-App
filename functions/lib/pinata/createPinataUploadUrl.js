"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.uploadBusinessLogoViaProxy = exports.createPinataUploadUrl = void 0;
const https_1 = require("firebase-functions/v2/https");
const zod_1 = require("zod");
const businessAuthorization_1 = require("../auth/businessAuthorization");
const errors_1 = require("../shared/errors");
const rateLimiter_1 = require("../shared/rateLimiter");
const secrets_1 = require("../shared/secrets");
const validation_1 = require("../shared/validation");
const requestSchema = zod_1.z.object({
    businessId: zod_1.z.string().min(1).max(128),
    fileName: zod_1.z.string().min(1).max(180),
    mimeType: zod_1.z.enum(["image/jpeg", "image/png", "image/webp"]),
    fileSize: zod_1.z.number().int().positive().max(2 * 1024 * 1024),
});
/**
 * Creates a short-lived Pinata upload URL. The Pinata JWT never leaves the server.
 */
exports.createPinataUploadUrl = (0, https_1.onCall)({
    region: "us-central1",
    secrets: [secrets_1.pinataJwt, secrets_1.pinataGateway],
    enforceAppCheck: false,
}, async (request) => {
    const uid = await (0, businessAuthorization_1.requireAuthenticatedUid)(request.auth?.uid);
    const parsed = requestSchema.safeParse(request.data);
    if (!parsed.success) {
        throw (0, errors_1.invalidArgument)("Invalid upload request.");
    }
    const { businessId, fileName, mimeType, fileSize } = parsed.data;
    const membership = await (0, businessAuthorization_1.requireBusinessMember)(uid, businessId);
    (0, businessAuthorization_1.requireOwnerOrManager)(membership.role, membership.isOwner);
    try {
        (0, validation_1.assertAllowedImage)(mimeType, fileSize);
    }
    catch (error) {
        throw (0, errors_1.invalidArgument)(error instanceof Error ? error.message : "Invalid image upload.");
    }
    await (0, rateLimiter_1.enforceRateLimit)({
        uid,
        businessId,
        operation: "createPinataUploadUrl",
        windowSeconds: 60,
        maxPerWindow: 8,
        dailyMax: 80,
    });
    const jwt = secrets_1.pinataJwt.value();
    let gateway = secrets_1.pinataGateway.value().replace(/\/$/, "");
    gateway = gateway.replace(/\/ipfs$/i, "");
    if (!jwt || !gateway) {
        throw (0, errors_1.unavailable)("Image upload is not configured yet.");
    }
    const safeName = (0, validation_1.sanitizeFileName)(fileName);
    const expiresInSeconds = 5 * 60;
    const expiresAt = Math.floor(Date.now() / 1000) + expiresInSeconds;
    try {
        const response = await fetch("https://uploads.pinata.cloud/v3/files/sign", {
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
        });
        if (!response.ok) {
            // Fallback: signed URL endpoint variants differ by Pinata plan.
            // Return a controlled upload session the client can use with multipart
            // against the standard pinFile endpoint via a short-lived custom token pattern.
            throw new Error(`pinata_sign_failed_${response.status}`);
        }
        const body = (await response.json());
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
    }
    catch (error) {
        // Controlled fallback: issue a one-shot server-mediated upload token stored in Firestore.
        // Flutter still never receives PINATA_JWT.
        const { getFirestore, FieldValue } = await Promise.resolve().then(() => __importStar(require("firebase-admin/firestore")));
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
            uploadMode: "callable_proxy",
            uploadSessionId: tokenRef.id,
            expiresAt: new Date(sessionExpires).toISOString(),
            fileName: safeName,
            mimeType,
            maxBytes: fileSize,
            gatewayBaseUrl: gateway,
            purpose: "business_logo",
            note: error instanceof Error && error.message.startsWith("pinata_sign_failed")
                ? "presign_unavailable_using_proxy"
                : "presign_unavailable_using_proxy",
        };
    }
});
/**
 * Completes a proxy upload when Pinata presign is unavailable for the account.
 * Accepts base64 image bytes only through this authenticated callable.
 */
exports.uploadBusinessLogoViaProxy = (0, https_1.onCall)({
    region: "us-central1",
    secrets: [secrets_1.pinataJwt, secrets_1.pinataGateway],
    enforceAppCheck: false,
    memory: "512MiB",
    timeoutSeconds: 60,
}, async (request) => {
    const uid = await (0, businessAuthorization_1.requireAuthenticatedUid)(request.auth?.uid);
    const schema = zod_1.z.object({
        businessId: zod_1.z.string().min(1),
        uploadSessionId: zod_1.z.string().min(1),
        base64Data: zod_1.z.string().min(1).max(4_000_000),
    });
    const parsed = schema.safeParse(request.data);
    if (!parsed.success) {
        throw (0, errors_1.invalidArgument)("Invalid upload payload.");
    }
    const { businessId, uploadSessionId, base64Data } = parsed.data;
    const membership = await (0, businessAuthorization_1.requireBusinessMember)(uid, businessId);
    (0, businessAuthorization_1.requireOwnerOrManager)(membership.role, membership.isOwner);
    await (0, rateLimiter_1.enforceRateLimit)({
        uid,
        businessId,
        operation: "uploadBusinessLogoViaProxy",
        windowSeconds: 60,
        maxPerWindow: 5,
        dailyMax: 40,
    });
    const { getFirestore, FieldValue } = await Promise.resolve().then(() => __importStar(require("firebase-admin/firestore")));
    const db = getFirestore();
    const sessionRef = db.collection("pinata_upload_sessions").doc(uploadSessionId);
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
        throw (0, errors_1.invalidArgument)("Upload session expired. Please try again.");
    }
    const session = sessionSnap.data();
    if (session.uid !== uid ||
        session.businessId !== businessId ||
        session.used === true ||
        session.expiresAtMs < Date.now()) {
        throw (0, errors_1.invalidArgument)("Upload session is no longer valid.");
    }
    const jwt = secrets_1.pinataJwt.value();
    let gateway = secrets_1.pinataGateway.value().replace(/\/$/, "");
    gateway = gateway.replace(/\/ipfs$/i, "");
    if (!jwt || !gateway) {
        throw (0, errors_1.unavailable)("Image upload is not configured yet.");
    }
    const bytes = Buffer.from(base64Data, "base64");
    if (bytes.byteLength <= 0 || bytes.byteLength > session.fileSize) {
        throw (0, errors_1.invalidArgument)("Uploaded image size is invalid.");
    }
    const form = new FormData();
    const blob = new Blob([bytes], { type: session.mimeType });
    form.append("file", blob, session.fileName);
    form.append("pinataMetadata", JSON.stringify({
        name: session.fileName,
        keyvalues: {
            businessId,
            uploadedBy: uid,
            purpose: "business_logo",
        },
    }));
    form.append("pinataOptions", JSON.stringify({ cidVersion: 1 }));
    const pinResponse = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
        method: "POST",
        headers: {
            Authorization: `Bearer ${jwt}`,
        },
        body: form,
    });
    if (!pinResponse.ok) {
        throw (0, errors_1.unavailable)("The image could not be uploaded. Please try again.");
    }
    const pinBody = (await pinResponse.json());
    const cid = pinBody.IpfsHash ?? pinBody.cid;
    if (!cid) {
        throw (0, errors_1.internal)();
    }
    await sessionRef.set({ used: true, usedAt: FieldValue.serverTimestamp(), cid }, { merge: true });
    const logoUrl = `${gateway}/ipfs/${cid}`;
    return {
        cid,
        logoUrl,
        fileName: session.fileName,
        mimeType: session.mimeType,
    };
});
//# sourceMappingURL=createPinataUploadUrl.js.map