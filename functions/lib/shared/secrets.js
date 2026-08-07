"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.pinataGateway = exports.pinataJwt = exports.groqModel = exports.groqApiKey = void 0;
const params_1 = require("firebase-functions/params");
exports.groqApiKey = (0, params_1.defineSecret)("GROQ_API_KEY");
exports.groqModel = (0, params_1.defineSecret)("GROQ_MODEL");
exports.pinataJwt = (0, params_1.defineSecret)("PINATA_JWT");
exports.pinataGateway = (0, params_1.defineSecret)("PINATA_GATEWAY");
//# sourceMappingURL=secrets.js.map