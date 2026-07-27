import fs from "fs";
import {cert, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";

function loadEnv(path) {
  const env = {};
  for (const line of fs.readFileSync(path, "utf8").split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf("=");
    if (i < 0) continue;
    let v = line.slice(i + 1);
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
      v = v.slice(1, -1);
    }
    v = v.replace(/\\n/g, "\n").replace(/\\r/g, "\r");
    env[line.slice(0, i)] = v;
  }
  return env;
}

function normalizePrivateKey(raw) {
  let key = (raw || "").trim();
  if (
    (key.startsWith('"') && key.endsWith('"')) ||
    (key.startsWith("'") && key.endsWith("'"))
  ) {
    key = key.slice(1, -1);
  }
  return key
    .replace(/\\\\n/g, "\n")
    .replace(/\\n/g, "\n")
    .replace(/\r\n/g, "\n")
    .trim();
}

const envPath = process.argv[2] || ".env.dev.check";
const apiKey = process.argv[3];
const uid = process.argv[4] || "u2rc788J3Jcrwa6kZG6yycb9kbb2";
const apiBase =
  process.argv[5] || "https://vercel-api-ten-ruddy.vercel.app";

if (!apiKey) {
  console.error(
    "Usage: node scripts/verify-key-and-auth.mjs <envfile> <webApiKey> [uid] [apiBase]",
  );
  process.exit(1);
}

const env = loadEnv(envPath);
const privateKey = normalizePrivateKey(env.FIREBASE_PRIVATE_KEY);
if (!getApps().length) {
  initializeApp({
    credential: cert({
      projectId: env.FIREBASE_PROJECT_ID,
      clientEmail: env.FIREBASE_CLIENT_EMAIL,
      privateKey,
    }),
    projectId: env.FIREBASE_PROJECT_ID,
  });
}

const customToken = await getAuth().createCustomToken(uid);
console.log("createCustomToken_ok");

const exchange = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
  {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({token: customToken, returnSecureToken: true}),
  },
);
const exchanged = await exchange.json();
if (!exchanged.idToken) {
  console.log(
    JSON.stringify(
      {step: "exchange", status: exchange.status, body: exchanged},
      null,
      2,
    ),
  );
  process.exit(1);
}

const idToken = exchanged.idToken;
await getAuth().verifyIdToken(idToken);
console.log("local_verifyIdToken_ok");

for (const path of ["/api/sabi/parse-receipt", "/api/pinata/upload-url"]) {
  const res = await fetch(`${apiBase}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({
      businessId: "test-business",
      command: "sold 2 rice",
      transcript: "sold 2 rice",
      fileName: "logo.jpg",
      mimeType: "image/jpeg",
      fileSize: 1200,
      purpose: "business_logo",
    }),
  });
  const body = await res.json().catch(() => ({}));
  console.log(
    JSON.stringify(
      {
        path,
        status: res.status,
        code: body?.error?.code ?? null,
        message: body?.error?.message ?? null,
      },
      null,
      2,
    ),
  );
}

fs.unlinkSync(envPath);
