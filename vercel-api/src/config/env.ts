import {z} from "zod";

function normalizeGateway(raw: string): string {
  let trimmed = raw.trim().replace(/\/$/, "");
  if (!trimmed) return "";
  if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
    trimmed = `https://${trimmed}`;
  }
  // Avoid `{gateway}/ipfs` + `/ipfs/{cid}` → `/ipfs/ipfs/{cid}` when the env
  // value already includes a trailing /ipfs path segment.
  trimmed = trimmed.replace(/\/ipfs$/i, "");
  return trimmed.replace(/\/$/, "");
}

/** Normalize PEM private keys stored in Vercel env (escaped newlines / quotes). */
export function normalizePrivateKey(raw: string): string {
  let key = raw.trim();
  if (
    (key.startsWith('"') && key.endsWith('"')) ||
    (key.startsWith("'") && key.endsWith("'"))
  ) {
    key = key.slice(1, -1);
  }
  // Handle double-escaped then single-escaped newlines from CLI/dashboard paste.
  key = key.replace(/\\\\n/g, "\n").replace(/\\n/g, "\n").replace(/\r\n/g, "\n");
  return key.trim();
}

const envSchema = z.object({
  GROQ_API_KEY: z.string().min(1),
  GROQ_MODEL: z.string().min(1).default("llama-3.3-70b-versatile"),
  PINATA_JWT: z.string().min(1),
  PINATA_GATEWAY: z.string().min(1),
  FIREBASE_PROJECT_ID: z.string().min(1),
  FIREBASE_CLIENT_EMAIL: z.string().email(),
  FIREBASE_PRIVATE_KEY: z.string().min(1),
  ALLOWED_ORIGINS: z.string().optional().default(""),
  APP_ENV: z.string().optional().default("development"),
  GOOGLE_PLAY_CLIENT_EMAIL: z.string().email().optional(),
  GOOGLE_PLAY_PRIVATE_KEY: z.string().min(1).optional(),
  GOOGLE_PLAY_PACKAGE_NAME: z.string().min(1).default("com.sabibom.app"),
  GOOGLE_PLAY_RTDN_TOKEN: z.string().min(20).optional(),
  BILLING_ENFORCEMENT_MODE: z.enum(["shadow", "enforced"]).default("shadow"),
});

export type AppEnv = {
  groqApiKey: string;
  groqModel: string;
  pinataJwt: string;
  pinataGateway: string;
  firebaseProjectId: string;
  firebaseClientEmail: string;
  firebasePrivateKey: string;
  allowedOrigins: string[];
  appEnv: string;
  googlePlayClientEmail: string;
  googlePlayPrivateKey: string;
  googlePlayPackageName: string;
  googlePlayRtdnToken: string | null;
  billingEnforcementMode: "shadow" | "enforced";
};

let cached: AppEnv | null = null;

export function getEnv(): AppEnv {
  if (cached) return cached;

  const parsed = envSchema.safeParse({
    GROQ_API_KEY: process.env.GROQ_API_KEY,
    GROQ_MODEL: process.env.GROQ_MODEL || "llama-3.3-70b-versatile",
    PINATA_JWT: process.env.PINATA_JWT,
    PINATA_GATEWAY: process.env.PINATA_GATEWAY,
    FIREBASE_PROJECT_ID: process.env.FIREBASE_PROJECT_ID,
    FIREBASE_CLIENT_EMAIL: process.env.FIREBASE_CLIENT_EMAIL,
    FIREBASE_PRIVATE_KEY: process.env.FIREBASE_PRIVATE_KEY,
    ALLOWED_ORIGINS: process.env.ALLOWED_ORIGINS ?? "",
    APP_ENV: process.env.APP_ENV ?? "development",
    GOOGLE_PLAY_CLIENT_EMAIL: process.env.GOOGLE_PLAY_CLIENT_EMAIL,
    GOOGLE_PLAY_PRIVATE_KEY: process.env.GOOGLE_PLAY_PRIVATE_KEY,
    GOOGLE_PLAY_PACKAGE_NAME:
      process.env.GOOGLE_PLAY_PACKAGE_NAME ?? "com.sabibom.app",
    GOOGLE_PLAY_RTDN_TOKEN: process.env.GOOGLE_PLAY_RTDN_TOKEN,
    BILLING_ENFORCEMENT_MODE:
      process.env.BILLING_ENFORCEMENT_MODE === "enforced" ? "enforced" : "shadow",
  });

  if (!parsed.success) {
    const missing = parsed.error.issues
      .map((issue) => issue.path.join("."))
      .filter(Boolean);
    throw new Error(
      `Missing or invalid environment configuration: ${missing.join(", ")}`,
    );
  }

  cached = {
    groqApiKey: parsed.data.GROQ_API_KEY,
    groqModel: parsed.data.GROQ_MODEL,
    pinataJwt: parsed.data.PINATA_JWT,
    pinataGateway: normalizeGateway(parsed.data.PINATA_GATEWAY),
    firebaseProjectId: parsed.data.FIREBASE_PROJECT_ID,
    firebaseClientEmail: parsed.data.FIREBASE_CLIENT_EMAIL,
    firebasePrivateKey: normalizePrivateKey(parsed.data.FIREBASE_PRIVATE_KEY),
    allowedOrigins: parsed.data.ALLOWED_ORIGINS.split(",")
      .map((item) => item.trim())
      .filter(Boolean),
    appEnv: parsed.data.APP_ENV,
    googlePlayClientEmail:
      parsed.data.GOOGLE_PLAY_CLIENT_EMAIL ?? parsed.data.FIREBASE_CLIENT_EMAIL,
    googlePlayPrivateKey: normalizePrivateKey(
      parsed.data.GOOGLE_PLAY_PRIVATE_KEY ?? parsed.data.FIREBASE_PRIVATE_KEY,
    ),
    googlePlayPackageName: parsed.data.GOOGLE_PLAY_PACKAGE_NAME,
    googlePlayRtdnToken: parsed.data.GOOGLE_PLAY_RTDN_TOKEN ?? null,
    billingEnforcementMode: parsed.data.BILLING_ENFORCEMENT_MODE,
  };
  return cached;
}

/** Soft env read for health — does not throw on missing secrets. */
export function getAppEnvName(): string {
  return process.env.APP_ENV?.trim() || "development";
}
