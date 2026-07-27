import type {VercelRequest, VercelResponse} from "@vercel/node";
import {normalizePrivateKey} from "../config/env";
import {createHandler} from "../utils/handler";
import {sendSuccess} from "../utils/api-response";

function firebaseConfigStatus() {
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim() ?? "";
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL?.trim() ?? "";
  const rawKey = process.env.FIREBASE_PRIVATE_KEY ?? "";
  const privateKey = normalizePrivateKey(rawKey);
  const looksLikePem =
    privateKey.includes("BEGIN PRIVATE KEY") &&
    privateKey.includes("END PRIVATE KEY") &&
    privateKey.includes("\n");
  const looksPlaceholder =
    !projectId ||
    projectId === "REPLACE_ME" ||
    !clientEmail ||
    clientEmail === "REPLACE_ME" ||
    !rawKey ||
    rawKey.trim() === "REPLACE_ME";

  return {
    projectIdSet: Boolean(projectId) && projectId !== "REPLACE_ME",
    clientEmailSet: Boolean(clientEmail) && clientEmail.includes("@"),
    privateKeyLooksValid: looksLikePem && !looksPlaceholder,
  };
}

function pinataConfigStatus() {
  const jwt = process.env.PINATA_JWT?.trim() ?? "";
  const gateway = process.env.PINATA_GATEWAY?.trim() ?? "";
  return {
    jwtSet: Boolean(jwt) && jwt !== "REPLACE_ME" && jwt.split(".").length === 3,
    gatewaySet: Boolean(gateway) && gateway !== "REPLACE_ME",
  };
}

export default createHandler(["GET"], async (_req: VercelRequest, res) => {
  sendSuccess(res, {
    status: "ok",
    service: "sabibom-api",
    timestamp: new Date().toISOString(),
    firebase: firebaseConfigStatus(),
    pinata: pinataConfigStatus(),
  });
});
