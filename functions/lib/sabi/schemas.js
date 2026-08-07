"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.businessQuestionMetricSchema = exports.businessQuestionRequestSchema = exports.sabiCommandResponseSchema = exports.sabiCommandRequestSchema = void 0;
const zod_1 = require("zod");
exports.sabiCommandRequestSchema = zod_1.z.object({
    businessId: zod_1.z.string().min(1).max(128),
    transcript: zod_1.z.string().trim().min(1).max(1200),
    draftSummary: zod_1.z
        .object({
        itemCount: zod_1.z.number().int().nonnegative().optional(),
        customerName: zod_1.z.string().nullable().optional(),
        paymentMethod: zod_1.z.string().nullable().optional(),
        totalMinor: zod_1.z.number().int().nonnegative().optional(),
    })
        .optional(),
});
exports.sabiCommandResponseSchema = zod_1.z.object({
    intent: zod_1.z.enum([
        "create_sale",
        "modify_sale",
        "select_customer",
        "set_payment",
        "select_template",
        "generate_pdf",
        "unknown",
    ]),
    confidence: zod_1.z.number().min(0).max(1),
    items: zod_1.z
        .array(zod_1.z.object({
        spokenName: zod_1.z.string().min(1).max(120),
        quantity: zod_1.z.number().positive().max(100000),
        spokenUnitPriceMinor: zod_1.z.number().int().nonnegative().nullable(),
        action: zod_1.z.enum(["add", "remove", "set_quantity"]),
    }))
        .max(40),
    customerQuery: zod_1.z.string().max(120).nullable(),
    payment: zod_1.z.object({
        method: zod_1.z
            .enum(["cash", "mobile_money", "bank_transfer", "card", "credit"])
            .nullable(),
        amountPaidMinor: zod_1.z.number().int().nonnegative().nullable(),
        isCredit: zod_1.z.boolean(),
    }),
    discount: zod_1.z.object({
        type: zod_1.z.enum(["fixed", "percentage"]).nullable(),
        value: zod_1.z.number().nonnegative().nullable(),
    }),
    receiptTemplateQuery: zod_1.z.string().max(80).nullable(),
    requiresConfirmation: zod_1.z.boolean(),
    clarifyingQuestion: zod_1.z.string().max(280).nullable(),
    warnings: zod_1.z.array(zod_1.z.string().max(200)).max(20),
});
exports.businessQuestionRequestSchema = zod_1.z.object({
    businessId: zod_1.z.string().min(1).max(128),
    question: zod_1.z.string().trim().min(3).max(500),
});
exports.businessQuestionMetricSchema = zod_1.z.object({
    metric: zod_1.z.enum([
        "sales_total",
        "sales_count",
        "customer_count",
        "product_count",
        "low_stock",
        "customer_balances",
        "best_sellers",
        "recent_sales",
        "cash_paid",
        "unknown",
    ]),
    period: zod_1.z.enum(["today", "week", "month", "all"]).default("today"),
});
//# sourceMappingURL=schemas.js.map