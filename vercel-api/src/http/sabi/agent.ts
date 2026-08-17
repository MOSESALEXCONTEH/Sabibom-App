import type {VercelRequest, VercelResponse} from "@vercel/node";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {enforceRateLimit} from "../../middleware/rate-limit";
import {
  inferSabiIntentHint,
  sabiAgentSystemPrompt,
} from "../../prompts/sabi-agent-prompt";
import {
  sabiAgentPlanSchema,
  sabiAgentRequestSchema,
  type SabiAgentPlan,
} from "../../schemas/sabi-agent-schema";
import {requireActiveBranchAccess} from "../../services/inventory/branch-inventory";
import {consumeSabiRequest} from "../../services/billing/entitlements";
import {
  loadMembership,
} from "../../services/team/membership-service";
import {membershipHasPermission} from "../../services/team/permissions";
import {
  runSabiReadTool,
  type AgentBranchScope,
} from "../../services/sabi-agent-tools";
import {findPublishedTrainingExamples} from "../../services/sabi-training-service";
import {recordUnansweredSabiAsk} from "../../services/sabi-unanswered-service";
import {groqChatJson} from "../../services/groq-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

function requiredPermission(tool: string): string | null {
  if (tool === "list_customers") return "view_customers";
  if (tool === "list_suppliers") return "view_suppliers";
  if (tool === "list_products") return "view_products";
  if (tool === "check_low_stock") return "view_low_stock_alerts";
  if (tool === "sales_report" || tool === "end_of_day_report") {
    return "view_sales_reports";
  }
  if (tool === "profit_report") return "view_profit";
  if (tool === "draft_customer") return "manage_customers";
  if (tool === "draft_supplier") return "manage_suppliers";
  if (tool === "draft_product") return "manage_products";
  if (tool === "draft_expense") return "create_expense";
  if (tool === "draft_sale") return "create_sale";
  if (tool === "draft_purchase") return "create_purchase";
  return null;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function number(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function clarificationAnswer(plan: SabiAgentPlan): string | null {
  let question = plan.clarification;
  let example = plan.suggestedPrompt;
  if (!question) {
    if (plan.tool === "draft_customer" && !text(plan.arguments.name)) {
      question = "What is the customer's name?";
      example = example ?? "Add customer James, phone 07892537";
    } else if (plan.tool === "draft_supplier" && !text(plan.arguments.name)) {
      question = "What is the supplier's name?";
      example = example ?? "Add supplier Aminata, phone 076123456";
    } else if (
      plan.tool === "draft_product" &&
      (!text(plan.arguments.name) ||
        number(plan.arguments.sellingPriceMinor) === null)
    ) {
      question = "What are the product name and selling price?";
      example = example ?? "Add product Soap, selling price 25";
    } else if (
      plan.tool === "draft_expense" &&
      number(plan.arguments.amountMinor) === null
    ) {
      question = "How much was the expense and what was it for?";
      example = example ?? "Add expense 200 for electricity";
    }
  }
  if (!question) return null;
  return example ? `${question}\n\nTry: "${example}"` : question;
}

function draftResponse(plan: SabiAgentPlan): Record<string, unknown> | null {
  const args = plan.arguments;
  const common = {
    verified: false,
    metric: null,
    requiresConfirmation: true,
    warnings: [] as string[],
  };
  if (plan.tool === "draft_customer") {
    const name = text(args.name);
    if (!name) return null;
    return {
      ...common,
      answer: plan.reply ?? "I prepared this customer. Review and confirm.",
      sabiAction: {
        intent: "add_customer",
        confidence: 1,
        reply: plan.reply ?? "I prepared this customer. Review and confirm.",
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
        customer: {
          name,
          phone: text(args.phone),
          email: text(args.email),
          address: text(args.address),
          notes: text(args.notes),
        },
        product: null,
        expense: null,
        supplier: null,
      },
    };
  }
  if (plan.tool === "draft_supplier") {
    const name = text(args.name);
    if (!name) return null;
    return {
      ...common,
      answer: plan.reply ?? "I prepared this supplier. Review and confirm.",
      sabiAction: {
        intent: "create_supplier",
        confidence: 1,
        reply: plan.reply ?? "I prepared this supplier. Review and confirm.",
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
        customer: null,
        product: null,
        expense: null,
        supplier: {name, phone: text(args.phone)},
      },
    };
  }
  if (plan.tool === "draft_product") {
    const name = text(args.name);
    if (!name || number(args.sellingPriceMinor) === null) return null;
    return {
      ...common,
      answer: plan.reply ?? "I prepared this product. Review and confirm.",
      sabiAction: {
        intent: "add_product",
        confidence: 1,
        reply: plan.reply ?? "I prepared this product. Review and confirm.",
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
        customer: null,
        product: {
          name,
          sellingPriceMinor: number(args.sellingPriceMinor),
          costPriceMinor: number(args.costPriceMinor),
          quantity: number(args.quantity),
          unit: text(args.unit),
          lowStockThreshold: number(args.lowStockThreshold),
          categoryName: text(args.categoryName),
          description: text(args.description),
        },
        expense: null,
        supplier: null,
      },
    };
  }
  if (plan.tool === "draft_expense") {
    const amountMinor = number(args.amountMinor);
    if (amountMinor === null || amountMinor <= 0) return null;
    return {
      ...common,
      answer: plan.reply ?? "I prepared this expense. Review and confirm.",
      sabiAction: {
        intent: "create_expense",
        confidence: 1,
        reply: plan.reply ?? "I prepared this expense. Review and confirm.",
        requiresConfirmation: true,
        clarifyingQuestion: null,
        warnings: [],
        customer: null,
        product: null,
        expense: {
          amountMinor,
          categoryName: text(args.categoryName),
          description: text(args.description),
          paymentMethod: text(args.paymentMethod),
        },
        supplier: null,
      },
    };
  }
  if (plan.tool === "draft_sale" || plan.tool === "draft_purchase") {
    return {
      ...common,
      answer:
        plan.reply ??
        `I prepared a ${plan.tool === "draft_sale" ? "sale" : "purchase"} draft for review.`,
      action:
        plan.tool === "draft_sale"
          ? "open_sale_draft"
          : "open_purchase_draft",
    };
  }
  return null;
}

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = sabiAgentRequestSchema.safeParse(readJsonBody(req));
    if (!parsed.success) {
      throw errors.invalidArgument("Please send a clear message to Sabi.");
    }
    const {businessId, branchId, message, conversation} = parsed.data;
    const membership = await loadMembership({uid: identity.uid, businessId});
    if (!membershipHasPermission(membership, "use_sabi")) {
      throw errors.permissionDenied();
    }

    const db = adminFirestore();
    await consumeSabiRequest({db, businessId, uid: identity.uid});
    let scope: AgentBranchScope;
    if (branchId === null) {
      if (!membershipHasPermission(membership, "view_combined_reports")) {
        throw errors.permissionDenied(
          "You do not have permission to ask across all branches.",
        );
      }
      scope = {branchId: null, isMainBranch: false};
    } else {
      const branch = await requireActiveBranchAccess({
        db,
        uid: identity.uid,
        businessId,
        branchId,
      });
      const data = (await branch.branchRef.get()).data() ?? {};
      scope = {
        branchId: branch.branchId,
        isMainBranch:
          data.isMainBranch === true ||
          String(data.code ?? "").toUpperCase() === "MAIN",
      };
    }

    await enforceRateLimit({
      uid: identity.uid,
      businessId,
      operation: "sabi_agent",
      windowSeconds: 60,
      maxPerWindow: 15,
      dailyMax: 300,
    });

    const trainingExamples = await findPublishedTrainingExamples({
      businessId,
      message,
    });
    const intentHint =
      trainingExamples[0]?.intent ?? inferSabiIntentHint(message);
    const rawPlan = await groqChatJson({
      system: sabiAgentSystemPrompt(),
      user: JSON.stringify({
        selectedBranch: scope.branchId ?? "all_branches_read_only",
        intentHint,
        trainingExamples: trainingExamples.map((example) => ({
          userWording: example.utterance,
          intendedTool: example.intent,
          clarification: example.clarification,
          correctedPrompt: example.suggestedPrompt,
        })),
        conversation,
        message,
      }),
    });
    const validated = sabiAgentPlanSchema.safeParse(rawPlan);
    if (!validated.success && !intentHint) {
      await recordUnansweredSabiAsk({
        businessId,
        userId: identity.uid,
        question: message,
        reply: "No supported intent could be resolved.",
        source: "agent_unresolved",
      });
      sendSuccess(res, {
        verified: false,
        answer:
          "I am not sure which business task you mean.\n\n" +
          'Try: "Add customer James, phone 07892537", ' +
          '"Add expense 200 for electricity", or "Show sales this week".',
        metric: null,
      });
      return;
    }
    const plan: SabiAgentPlan = validated.success
      ? validated.data
      : {
          tool: intentHint as SabiAgentPlan["tool"],
          reply: null,
          clarification: null,
          suggestedPrompt: null,
          arguments: {},
        };
    const clarification = clarificationAnswer(plan);
    if (clarification) {
      sendSuccess(res, {
        verified: false,
        answer: clarification,
        clarification,
        metric: null,
      });
      return;
    }

    const permission = requiredPermission(plan.tool);
    if (permission && !membershipHasPermission(membership, permission)) {
      throw errors.permissionDenied(
        "You do not have permission to perform that action.",
      );
    }

    const readAnswer = await runSabiReadTool({
      businessId,
      scope,
      tool: plan.tool,
      args: plan.arguments,
    });
    if (readAnswer !== null) {
      sendSuccess(res, {
        verified: true,
        answer: readAnswer,
        metric: null,
      });
      return;
    }

    const draft = draftResponse(plan);
    if (draft !== null) {
      if (branchId === null) {
        throw errors.branchRequired(
          "Switch to a single branch before preparing a new record.",
        );
      }
      sendSuccess(res, draft);
      return;
    }

    sendSuccess(res, {
      verified: false,
      answer:
        plan.reply ??
        "Tell me what you want to check or prepare for your business.",
      metric: null,
    });
  },
);
