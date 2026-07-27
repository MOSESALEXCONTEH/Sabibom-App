import type {VercelRequest, VercelResponse} from "@vercel/node";
import {getAppEnvName, getEnv} from "../config/env";

export function applyCors(req: VercelRequest, res: VercelResponse): boolean {
  const origin = req.headers.origin;
  let allowedOrigins: string[] = [];
  try {
    allowedOrigins = getEnv().allowedOrigins;
  } catch {
    allowedOrigins = (process.env.ALLOWED_ORIGINS ?? "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  const appEnv = getAppEnvName();
  if (origin && allowedOrigins.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
    res.setHeader("Access-Control-Allow-Credentials", "true");
  } else if (appEnv !== "production" && origin) {
    // Local/dev convenience only — never wildcard + credentials in production.
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }

  res.setHeader(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type",
  );
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");

  if (req.method === "OPTIONS") {
    res.status(204).end();
    return true;
  }
  return false;
}
