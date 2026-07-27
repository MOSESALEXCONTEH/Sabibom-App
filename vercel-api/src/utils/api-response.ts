import type {VercelResponse} from "@vercel/node";
import {ApiError} from "./api-errors";

const securityHeaders = {
  "X-Content-Type-Options": "nosniff",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};

export function sendSuccess(
  res: VercelResponse,
  data: unknown,
  status = 200,
): void {
  res.status(status).setHeader("Content-Type", "application/json");
  for (const [key, value] of Object.entries(securityHeaders)) {
    res.setHeader(key, value);
  }
  res.json({success: true, data});
}

export function sendError(res: VercelResponse, error: unknown): void {
  for (const [key, value] of Object.entries(securityHeaders)) {
    res.setHeader(key, value);
  }
  res.setHeader("Content-Type", "application/json");

  if (error instanceof ApiError) {
    res.status(error.status).json({
      success: false,
      error: {code: error.code, message: error.message},
    });
    return;
  }

  console.error("[sabibom-api] unexpected error", {
    name: error instanceof Error ? error.name : "unknown",
    message: error instanceof Error ? error.message : "unknown",
  });

  res.status(500).json({
    success: false,
    error: {
      code: "internal",
      message: "Something went wrong while processing the request.",
    },
  });
}
