import type {VercelRequest, VercelResponse} from "@vercel/node";
import {applyCors} from "../middleware/cors";
import {errors} from "./api-errors";
import {sendError} from "./api-response";

export function createHandler(
  methods: string[],
  handler: (req: VercelRequest, res: VercelResponse) => Promise<void>,
) {
  return async (req: VercelRequest, res: VercelResponse): Promise<void> => {
    try {
      if (applyCors(req, res)) return;
      const method = req.method?.toUpperCase() ?? "";
      if (!methods.includes(method)) {
        throw errors.methodNotAllowed();
      }
      await handler(req, res);
    } catch (error) {
      sendError(res, error);
    }
  };
}

export function readJsonBody(req: VercelRequest): unknown {
  if (req.body == null) return {};
  if (typeof req.body === "string") {
    try {
      return JSON.parse(req.body);
    } catch {
      throw errors.invalidArgument();
    }
  }
  return req.body;
}
