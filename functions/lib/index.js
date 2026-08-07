"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.answerSabiBusinessQuestion = exports.parseSabiReceiptCommand = exports.uploadBusinessLogoViaProxy = exports.createPinataUploadUrl = void 0;
const app_1 = require("firebase-admin/app");
const v2_1 = require("firebase-functions/v2");
(0, app_1.initializeApp)();
(0, v2_1.setGlobalOptions)({
    region: "us-central1",
    maxInstances: 20,
});
var createPinataUploadUrl_1 = require("./pinata/createPinataUploadUrl");
Object.defineProperty(exports, "createPinataUploadUrl", { enumerable: true, get: function () { return createPinataUploadUrl_1.createPinataUploadUrl; } });
Object.defineProperty(exports, "uploadBusinessLogoViaProxy", { enumerable: true, get: function () { return createPinataUploadUrl_1.uploadBusinessLogoViaProxy; } });
var parseSabiReceiptCommand_1 = require("./sabi/parseSabiReceiptCommand");
Object.defineProperty(exports, "parseSabiReceiptCommand", { enumerable: true, get: function () { return parseSabiReceiptCommand_1.parseSabiReceiptCommand; } });
var answerSabiBusinessQuestion_1 = require("./sabi/answerSabiBusinessQuestion");
Object.defineProperty(exports, "answerSabiBusinessQuestion", { enumerable: true, get: function () { return answerSabiBusinessQuestion_1.answerSabiBusinessQuestion; } });
//# sourceMappingURL=index.js.map