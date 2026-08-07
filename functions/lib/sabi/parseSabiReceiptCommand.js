"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseSabiReceiptCommand = void 0;
const https_1 = require("firebase-functions/v2/https");
const businessAuthorization_1 = require("../auth/businessAuthorization");
const errors_1 = require("../shared/errors");
const rateLimiter_1 = require("../shared/rateLimiter");
const secrets_1 = require("../shared/secrets");
const prompts_1 = require("./prompts");
const schemas_1 = require("./schemas");
exports.parseSabiReceiptCommand = (0, https_1.onCall)({
    region: "us-central1",
    secrets: [secrets_1.groqApiKey, secrets_1.groqModel],
    enforceAppCheck: false,
    timeoutSeconds: 45,
}, async (request) => {
    const uid = await (0, businessAuthorization_1.requireAuthenticatedUid)(request.auth?.uid);
    const parsed = schemas_1.sabiCommandRequestSchema.safeParse(request.data);
    if (!parsed.success) {
        throw (0, errors_1.invalidArgument)("Please enter or speak a clear instruction.");
    }
    const { businessId, transcript, draftSummary } = parsed.data;
    await (0, businessAuthorization_1.requireBusinessMember)(uid, businessId);
    await (0, rateLimiter_1.enforceRateLimit)({
        uid,
        businessId,
        operation: "parseSabiReceiptCommand",
        windowSeconds: 60,
        maxPerWindow: 12,
        dailyMax: 250,
    });
    const apiKey = secrets_1.groqApiKey.value();
    const model = secrets_1.groqModel.value() || "llama-3.3-70b-versatile";
    if (!apiKey) {
        throw (0, errors_1.unavailable)("Sabi is temporarily unavailable. You can continue the sale manually.");
    }
    const userPayload = {
        transcript,
        draftSummary: draftSummary ?? null,
        schemaHint: {
            intent: "create_sale|modify_sale|select_customer|set_payment|select_template|generate_pdf|unknown",
            items: [
                {
                    spokenName: "string",
                    quantity: 1,
                    spokenUnitPriceMinor: null,
                    action: "add|remove|set_quantity",
                },
            ],
            customerQuery: null,
            payment: { method: null, amountPaidMinor: null, isCredit: false },
            discount: { type: null, value: null },
            receiptTemplateQuery: null,
            requiresConfirmation: true,
            clarifyingQuestion: null,
            warnings: [],
            confidence: 0.0,
        },
    };
    let content = "";
    try {
        const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${apiKey}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model,
                temperature: 0.1,
                response_format: { type: "json_object" },
                messages: [
                    { role: "system", content: (0, prompts_1.receiptCommandSystemPrompt)() },
                    { role: "user", content: JSON.stringify(userPayload) },
                ],
            }),
        });
        if (!response.ok) {
            throw (0, errors_1.unavailable)("Sabi is temporarily unavailable. You can continue the sale manually.");
        }
        const body = (await response.json());
        content = body.choices?.[0]?.message?.content?.trim() ?? "";
    }
    catch (error) {
        if (error && typeof error === "object" && "code" in error) {
            throw error;
        }
        throw (0, errors_1.unavailable)("Sabi is temporarily unavailable. You can continue the sale manually.");
    }
    if (!content) {
        throw (0, errors_1.invalidArgument)("I couldn’t understand that safely. Please rephrase or enter the sale manually.");
    }
    let json;
    try {
        json = JSON.parse(content);
    }
    catch {
        throw (0, errors_1.invalidArgument)("I couldn’t understand that safely. Please rephrase or enter the sale manually.");
    }
    const validated = schemas_1.sabiCommandResponseSchema.safeParse(json);
    if (!validated.success) {
        throw (0, errors_1.invalidArgument)("I couldn’t understand that safely. Please rephrase or enter the sale manually.");
    }
    // Financial safety: AI never auto-completes.
    const result = {
        ...validated.data,
        requiresConfirmation: true,
    };
    for (const item of result.items) {
        if (item.quantity <= 0) {
            throw (0, errors_1.invalidArgument)("Quantity must be greater than zero.");
        }
        if (item.spokenUnitPriceMinor != null &&
            item.spokenUnitPriceMinor < 0) {
            throw (0, errors_1.invalidArgument)("Price cannot be negative.");
        }
    }
    return result;
});
//# sourceMappingURL=parseSabiReceiptCommand.js.map