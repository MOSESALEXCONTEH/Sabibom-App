import type {VercelRequest, VercelResponse} from "@vercel/node";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {
  businessAnswerSystemPrompt,
  generalBusinessAdviceSystemPrompt,
  unknownMetricFallbackAnswer,
} from "../../prompts/business-question-prompt";
import {businessQuestionRequestSchema} from "../../schemas/business-question-schema";
import {requireBusinessAccess} from "../../services/business-access-service";
import {consumeSabiRequest} from "../../services/billing/entitlements";
import {
  detectMetric,
  loadVerifiedMetric,
} from "../../services/business-data-service";
import {loadMembership} from "../../services/team/membership-service";
import {membershipHasPermission} from "../../services/team/permissions";
import {groqChatText} from "../../services/groq-service";
import {recordUnansweredSabiAsk} from "../../services/sabi-unanswered-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

function looksLikeSaleOrReceiptRequest(question: string): boolean {
  const q = question.toLowerCase();
  // Purchase / stock-buy language is handled elsewhere — do not treat as sale.
  if (
    q.includes("purchase") ||
    q.includes("supplier") ||
    (/\b(buy|bought)\b/.test(q) &&
      (q.includes("stock") || q.includes("from") || q.includes("supplier")))
  ) {
    return false;
  }
  return (
    q.includes("receipt") ||
    q.includes("invoice") ||
    q.includes("create sale") ||
    q.includes("make a sale") ||
    q.includes("sell ") ||
    q.includes("sold ") ||
    (/\b(buy|bought)\b/.test(q) &&
      (q.includes("customer") || q.includes("receipt") || q.includes("sale")))
  );
}

export default createHandler(["POST"], async (req: VercelRequest, res: VercelResponse) => {
  const identity = await authenticateRequest(req);
  const parsed = businessQuestionRequestSchema.safeParse(readJsonBody(req));
  if (!parsed.success) {
    throw errors.invalidArgument("Please ask a clearer business question.");
  }

  const {businessId, question, replyLanguage = "en"} = parsed.data;
  await requireBusinessAccess({
    uid: identity.uid,
    businessId,
    requiredPermission: "use_sabi",
  });
  await consumeSabiRequest({
    db: adminFirestore(),
    businessId,
    uid: identity.uid,
  });

  await enforceRateLimit({
    uid: identity.uid,
    businessId,
    operation: "business_question",
    windowSeconds: 60,
    maxPerWindow: 15,
    dailyMax: 300,
  });

  if (looksLikeSaleOrReceiptRequest(question)) {
    sendSuccess(res, {
      verified: false,
      answer:
        replyLanguage === "krio"
          ? "A kin draft da sale/receipt for yu. Open Create Sale with Sabi, tell me di items and prices, then review and confirm."
          : "I can draft that sale/receipt for you. Open Create Sale with Sabi, tell me the items and prices (for example: sold 2 rice at 50 and 1 oil at 30), then review and confirm.",
      metric: null,
      action: "open_sale_draft",
    });
    return;
  }

  const detected = detectMetric(question);
  const profitMetrics = new Set([
    "net_profit",
    "gross_profit",
    "profit",
    "cogs",
  ]);
  if (
    profitMetrics.has(detected.metric) ||
    /profit|margin|cogs|cost of goods/i.test(question)
  ) {
    const full = await loadMembership({uid: identity.uid, businessId});
    if (
      !membershipHasPermission(full, "view_profit") &&
      !membershipHasPermission(full, "ask_sabi_profit_questions")
    ) {
      sendSuccess(res, {
        verified: false,
        answer:
          "You do not have permission to perform this action. Contact the business owner or manager.",
        metric: null,
        permissionDenied: true,
      });
      return;
    }
  }
  if (detected.metric === "unknown") {
    const advice =
      (await groqChatText({
        system: generalBusinessAdviceSystemPrompt(replyLanguage),
        user: JSON.stringify({
          question,
          context:
            "No verified Firestore metric matched. Do not invent data. Offer only what Sabi can check.",
        }),
        temperature: 0.2,
      })) || unknownMetricFallbackAnswer(replyLanguage);

    // Best-effort training capture — never block the merchant reply.
    try {
      await recordUnansweredSabiAsk({
        businessId,
        userId: identity.uid,
        question,
        reply: advice,
        replyLanguage,
        source: "business_question_unknown",
      });
    } catch (_) {
      // ignore persistence failures
    }

    sendSuccess(res, {
      verified: false,
      answer: advice,
      metric: null,
    });
    return;
  }

  const verified = await loadVerifiedMetric(
    businessId,
    detected.metric,
    detected.period,
  );

  let answer =
    verified.unit === "amount"
      ? `${verified.currencySymbol} ${Number(verified.value).toFixed(2)} for ${verified.periodLabel.toLowerCase()}.`
      : `${verified.value} ${verified.unit} for ${verified.periodLabel.toLowerCase()}.`;
  if (verified.details && verified.details.length > 0) {
    answer += ` ${verified.details.slice(0, 6).join("; ")}.`;
  }

  const wording = await groqChatText({
    system: businessAnswerSystemPrompt(replyLanguage),
    user: JSON.stringify({
      question,
      verifiedMetric: verified,
      instruction:
        "Answer using verifiedMetric. If details are present, name the important items.",
    }),
  });
  if (wording) answer = wording;

  sendSuccess(res, {
    verified: true,
    answer,
    metric: {
      metric: verified.metric,
      period: verified.period,
      value: verified.value,
      valueMinor: verified.valueMinor ?? null,
      currencyCode: verified.currencyCode,
      currencySymbol: verified.currencySymbol,
      unit: verified.unit,
      source: verified.source,
      recordCount: verified.recordCount,
      lastUpdatedIso: verified.lastUpdatedIso,
      details: verified.details ?? [],
      periodLabel: verified.periodLabel,
      start: verified.startIso,
      end: verified.endIso,
    },
  });
});
