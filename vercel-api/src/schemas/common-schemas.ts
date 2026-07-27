import {z} from "zod";

export const businessIdSchema = z.string().trim().min(1).max(128);
