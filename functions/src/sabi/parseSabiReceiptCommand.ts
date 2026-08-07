import {onCall} from "firebase-functions/v2/https";
import {
  requireAuthenticatedUid,
  requireBusinessMember,
} from "../auth/businessAuthorization";
import {invalidArgument, unavailable} from "../shared/errors";
import {enforceRateLimit} from "../shared/rateLimiter";
import {groqApiKey, groqModel} from "../shared/secrets";
import {receiptCommandSystemPrompt} from "./prompts";
import {
  sabiCommandRequestSchema,
  sabiCommandResponseSchema,
} from "./schemas";

export const parseSabiReceiptCommand = onCall(
  {
    region: "us-central1",
    secrets: [groqApiKey, groqModel],
    enforceAppCheck: false,
    timeoutSeconds: 45,
  },
  async (request) => {
    const uid = await requireAuthenticatedUid(request.auth?.uid);
    const parsed = sabiCommandRequestSchema.safeParse(request.data);
    if (!parsed.success) {
      throw invalidArgument("Please enter or speak a clear instruction.");
    }

    const {businessId, transcript, draftSummary} = parsed.data;
    await requireBusinessMember(uid, businessId);
    await enforceRateLimit({
      uid,
      businessId,
      operation: "parseSabiReceiptCommand",
      windowSeconds: 60,
      maxPerWindow: 12,
      dailyMax: 250,
    });

    const apiKey = groqApiKey.value();
    const model = groqModel.value() || "llama-3.3-70b-versatile";
    if (!apiKey) {
      throw unavailable(
        "Sabi is temporarily unavailable. You can continue the sale manually.",
      );
    }

    const userPayload = {
      transcript,
      draftSummary: draftSummary ?? null,
      schemaHint: {
        intent:
          "create_sale|modify_sale|select_customer|set_payment|select_template|generate_pdf|unknown",
        items: [
          {
            spokenName: "string",
            quantity: 1,
            spokenUnitPriceMinor: null,
            action: "add|remove|set_quantity",
          },
        ],
        customerQuery: null,
        payment: {method: null, amountPaidMinor: null, isCredit: false},
        discount: {type: null, value: null},
        receiptTemplateQuery: null,
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
        confidence: 0.0,
      },
    };

    let content = "";
    try {
      const response = await fetch(
        "https://api.groq.com/openai/v1/chat/completions",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model,
            temperature: 0.1,
            response_format: {type: "json_object"},
            messages: [
              {role: "system", content: receiptCommandSystemPrompt()},
              {role: "user", content: JSON.stringify(userPayload)},
            ],
          }),
        },
      );

      if (!response.ok) {
        throw unavailable(
          "Sabi is temporarily unavailable. You can continue the sale manually.",
        );
      }

      const body = (await response.json()) as {
        choices?: Array<{message?: {content?: string}}>;
      };
      content = body.choices?.[0]?.message?.content?.trim() ?? "";
    } catch (error) {
      if (error && typeof error === "object" && "code" in error) {
        throw error;
      }
      throw unavailable(
        "Sabi is temporarily unavailable. You can continue the sale manually.",
      );
    }

    if (!content) {
      throw invalidArgument(
        "I couldn’t understand that safely. Please rephrase or enter the sale manually.",
      );
    }

    let json: unknown;
    try {
      json = JSON.parse(content);
    } catch {
      throw invalidArgument(
        "I couldn’t understand that safely. Please rephrase or enter the sale manually.",
      );
    }

    const validated = sabiCommandResponseSchema.safeParse(json);
    if (!validated.success) {
      throw invalidArgument(
        "I couldn’t understand that safely. Please rephrase or enter the sale manually.",
      );
    }

    // Financial safety: AI never auto-completes.
    const result = {
      ...validated.data,
      requiresConfirmation: true,
    };

    for (const item of result.items) {
      if (item.quantity <= 0) {
        throw invalidArgument("Quantity must be greater than zero.");
      }
      if (
        item.spokenUnitPriceMinor != null &&
        item.spokenUnitPriceMinor < 0
      ) {
        throw invalidArgument("Price cannot be negative.");
      }
    }

    return result;
  },
);
