"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = require("node:test");
const schemas_1 = require("./schemas");
(0, node_test_1.describe)("sabiCommandResponseSchema", () => {
    (0, node_test_1.it)("accepts a valid create_sale payload", () => {
        const parsed = schemas_1.sabiCommandResponseSchema.parse({
            intent: "create_sale",
            confidence: 0.9,
            items: [
                {
                    spokenName: "rice",
                    quantity: 2,
                    spokenUnitPriceMinor: null,
                    action: "add",
                },
            ],
            customerQuery: null,
            payment: { method: "cash", amountPaidMinor: 10000, isCredit: false },
            discount: { type: null, value: null },
            receiptTemplateQuery: null,
            requiresConfirmation: true,
            clarifyingQuestion: null,
            warnings: [],
        });
        strict_1.default.equal(parsed.intent, "create_sale");
    });
    (0, node_test_1.it)("rejects negative quantities", () => {
        strict_1.default.throws(() => schemas_1.sabiCommandResponseSchema.parse({
            intent: "create_sale",
            confidence: 0.5,
            items: [
                {
                    spokenName: "oil",
                    quantity: -1,
                    spokenUnitPriceMinor: null,
                    action: "add",
                },
            ],
            customerQuery: null,
            payment: { method: null, amountPaidMinor: null, isCredit: false },
            discount: { type: null, value: null },
            receiptTemplateQuery: null,
            requiresConfirmation: true,
            clarifyingQuestion: null,
            warnings: [],
        }));
    });
    (0, node_test_1.it)("rejects invalid intents", () => {
        strict_1.default.throws(() => schemas_1.sabiCommandResponseSchema.parse({
            intent: "complete_sale",
            confidence: 1,
            items: [],
            customerQuery: null,
            payment: { method: null, amountPaidMinor: null, isCredit: false },
            discount: { type: null, value: null },
            receiptTemplateQuery: null,
            requiresConfirmation: true,
            clarifyingQuestion: null,
            warnings: [],
        }));
    });
});
//# sourceMappingURL=schemas.test.js.map