import {defineSecret} from "firebase-functions/params";

export const groqApiKey = defineSecret("GROQ_API_KEY");
export const groqModel = defineSecret("GROQ_MODEL");
export const pinataJwt = defineSecret("PINATA_JWT");
export const pinataGateway = defineSecret("PINATA_GATEWAY");
