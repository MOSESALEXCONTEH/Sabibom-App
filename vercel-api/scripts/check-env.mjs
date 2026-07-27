import fs from "fs";

const path = process.argv[2] || ".env.check";
const text = fs.readFileSync(path, "utf8");
const env = {};
for (const line of text.split(/\r?\n/)) {
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
  // dotenv-style unescape for pulled files
  v = v.replace(/\\n/g, "\n").replace(/\\r/g, "\r");
  env[line.slice(0, i)] = v;
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

const pk = normalizePrivateKey(env.FIREBASE_PRIVATE_KEY || "");
const report = {
  FIREBASE_PROJECT_ID: env.FIREBASE_PROJECT_ID || null,
  FIREBASE_CLIENT_EMAIL: env.FIREBASE_CLIENT_EMAIL || null,
  privateKeyLen: (env.FIREBASE_PRIVATE_KEY || "").length,
  privateKeyHasBegin: pk.includes("BEGIN PRIVATE KEY"),
  privateKeyHasEnd: pk.includes("END PRIVATE KEY"),
  privateKeyHasRealNewlines: pk.includes("\n"),
  privateKeyLineCount: pk.split("\n").length,
  privateKeyStarts: pk.slice(0, 27),
  GROQ_API_KEY_is_placeholder:
    !env.GROQ_API_KEY || env.GROQ_API_KEY === "REPLACE_ME",
  PINATA_JWT_is_placeholder:
    !env.PINATA_JWT || env.PINATA_JWT === "REPLACE_ME",
  PINATA_GATEWAY_is_placeholder:
    !env.PINATA_GATEWAY || env.PINATA_GATEWAY === "REPLACE_ME",
  PINATA_GATEWAY_shape: (env.PINATA_GATEWAY || "").includes("pinata")
    ? "looks-like-gateway"
    : env.PINATA_GATEWAY === "REPLACE_ME"
      ? "REPLACE_ME"
      : "other",
};

console.log(JSON.stringify(report, null, 2));
fs.unlinkSync(path);
