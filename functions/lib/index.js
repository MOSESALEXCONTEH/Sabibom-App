"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onStaffInvitationWritten = exports.onRoleWritten = exports.onMembershipWritten = exports.onStaffActivityCreated = exports.onApprovalRequestWritten = exports.answerSabiBusinessQuestion = exports.parseSabiReceiptCommand = exports.uploadBusinessLogoViaProxy = exports.createPinataUploadUrl = void 0;
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
var approvalTriggers_1 = require("./notifications/approvalTriggers");
Object.defineProperty(exports, "onApprovalRequestWritten", { enumerable: true, get: function () { return approvalTriggers_1.onApprovalRequestWritten; } });
var staffActivityTriggers_1 = require("./notifications/staffActivityTriggers");
Object.defineProperty(exports, "onStaffActivityCreated", { enumerable: true, get: function () { return staffActivityTriggers_1.onStaffActivityCreated; } });
var lifecycleTriggers_1 = require("./notifications/lifecycleTriggers");
Object.defineProperty(exports, "onMembershipWritten", { enumerable: true, get: function () { return lifecycleTriggers_1.onMembershipWritten; } });
Object.defineProperty(exports, "onRoleWritten", { enumerable: true, get: function () { return lifecycleTriggers_1.onRoleWritten; } });
Object.defineProperty(exports, "onStaffInvitationWritten", { enumerable: true, get: function () { return lifecycleTriggers_1.onStaffInvitationWritten; } });
//# sourceMappingURL=index.js.map