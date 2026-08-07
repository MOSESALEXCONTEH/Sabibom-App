"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.answerSabiBusinessQuestion = void 0;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const businessAuthorization_1 = require("../auth/businessAuthorization");
const errors_1 = require("../shared/errors");
const rateLimiter_1 = require("../shared/rateLimiter");
const secrets_1 = require("../shared/secrets");
const prompts_1 = require("./prompts");
const schemas_1 = require("./schemas");
function detectMetric(question) {
    const q = question.toLowerCase();
    const mentionsToday = q.includes("today");
    const mentionsWeek = q.includes("week");
    const mentionsMonth = q.includes("month");
    const period = mentionsWeek
        ? "week"
        : mentionsMonth
            ? "month"
            : mentionsToday
                ? "today"
                : "today";
    const countPeriod = mentionsWeek || mentionsMonth || mentionsToday ? period : "all";
    const asksCount = q.includes("how many") ||
        q.includes("number of") ||
        q.includes("count of") ||
        (q.includes("do i have") && !q.includes("owe"));
    if (q.includes("owe") || q.includes("balance") || (q.includes("credit") && q.includes("who"))) {
        return { metric: "customer_balances", period: "all" };
    }
    if (q.includes("low stock") || q.includes("out of stock") || q.includes("running low")) {
        return { metric: "low_stock", period: "all" };
    }
    if (q.includes("best") || q.includes("top selling") || q.includes("best-selling")) {
        return { metric: "best_sellers", period };
    }
    if (q.includes("recent sales") || q.includes("latest sales")) {
        return { metric: "recent_sales", period };
    }
    if (q.includes("cash")) {
        return { metric: "cash_paid", period };
    }
    if (asksCount && (q.includes("customer") || q.includes("client"))) {
        return { metric: "customer_count", period: "all" };
    }
    if (asksCount && (q.includes("product") || q.includes("item")) && !q.includes("sale")) {
        return { metric: "product_count", period: "all" };
    }
    if (q.includes("number of sales") ||
        q.includes("orders") ||
        (asksCount && (q.includes("sale") || q.includes("order") || q.includes("receipt")))) {
        return { metric: "sales_count", period: countPeriod };
    }
    if (q.includes("sell") || q.includes("sales") || q.includes("revenue")) {
        return { metric: "sales_total", period };
    }
    return { metric: "unknown", period };
}
function periodBounds(period) {
    const end = new Date();
    const start = new Date(end);
    if (period === "week") {
        const day = start.getDay();
        const diff = day === 0 ? 6 : day - 1;
        start.setDate(start.getDate() - diff);
        start.setHours(0, 0, 0, 0);
    }
    else if (period === "month") {
        start.setDate(1);
        start.setHours(0, 0, 0, 0);
    }
    else if (period === "all") {
        start.setFullYear(start.getFullYear() - 10);
        start.setHours(0, 0, 0, 0);
    }
    else {
        start.setHours(0, 0, 0, 0);
    }
    return { start, end };
}
async function loadVerifiedMetric(businessId, metric, period) {
    const db = (0, firestore_1.getFirestore)();
    const businessRef = db.collection("businesses").doc(businessId);
    const businessSnap = await businessRef.get();
    const currencySymbol = businessSnap.data()?.currencySymbol ?? "Le";
    const nowIso = new Date().toISOString();
    if (metric === "low_stock") {
        const products = await businessRef.collection("products").limit(200).get();
        const low = products.docs.filter((doc) => {
            const data = doc.data();
            const track = data.trackStock !== false;
            const status = data.status ?? "active";
            if (!track || status !== "active")
                return false;
            const qty = data.quantity ?? 0;
            const threshold = data.lowStockThreshold ?? 0;
            return qty <= threshold;
        });
        return {
            metric,
            period: "all",
            value: low.length,
            currencySymbol,
            unit: "products",
            source: "products",
            lastUpdatedIso: nowIso,
            details: low.slice(0, 5).map((doc) => {
                const data = doc.data();
                return `${data.name ?? "Product"} (${data.quantity ?? 0})`;
            }),
        };
    }
    if (metric === "customer_balances") {
        const customers = await businessRef.collection("customers").limit(200).get();
        const owing = customers.docs
            .map((doc) => {
            const data = doc.data();
            const balanceMinor = data.balanceMinor ??
                Math.round((data.balance ?? 0) * 100);
            return {
                name: data.name ?? "Customer",
                balanceMinor,
            };
        })
            .filter((row) => row.balanceMinor > 0)
            .sort((a, b) => b.balanceMinor - a.balanceMinor);
        const totalMinor = owing.reduce((sum, row) => sum + row.balanceMinor, 0);
        return {
            metric,
            period: "all",
            value: totalMinor / 100,
            currencySymbol,
            unit: "amount",
            source: "customers",
            lastUpdatedIso: nowIso,
            details: owing
                .slice(0, 5)
                .map((row) => `${row.name}: ${currencySymbol} ${(row.balanceMinor / 100).toFixed(2)}`),
        };
    }
    if (metric === "customer_count") {
        const customers = await businessRef.collection("customers").limit(500).get();
        const active = customers.docs.filter((doc) => {
            const status = doc.data().status ?? "active";
            return status !== "archived" && status !== "deleted";
        });
        return {
            metric,
            period: "all",
            value: active.length,
            currencySymbol,
            unit: "customers",
            source: "customers",
            lastUpdatedIso: nowIso,
        };
    }
    if (metric === "product_count") {
        const products = await businessRef.collection("products").limit(500).get();
        const active = products.docs.filter((doc) => {
            const status = doc.data().status ?? "active";
            return status === "active";
        });
        return {
            metric,
            period: "all",
            value: active.length,
            currencySymbol,
            unit: "products",
            source: "products",
            lastUpdatedIso: nowIso,
        };
    }
    const { start, end } = periodBounds(period);
    const salesSnap = await businessRef
        .collection("sales")
        .where("createdAt", ">=", firestore_1.Timestamp.fromDate(start))
        .where("createdAt", "<", firestore_1.Timestamp.fromDate(end))
        .limit(300)
        .get();
    const sales = salesSnap.docs.filter((doc) => {
        const status = doc.data().status ?? "completed";
        return status === "completed";
    });
    if (metric === "sales_count") {
        return {
            metric,
            period,
            value: sales.length,
            currencySymbol,
            unit: "sales",
            source: "sales",
            lastUpdatedIso: nowIso,
        };
    }
    if (metric === "cash_paid") {
        const cash = sales.filter((doc) => doc.data().paymentMethod === "cash");
        const total = cash.reduce((sum, doc) => {
            const data = doc.data();
            const minor = data.amountPaidMinor ??
                Math.round((data.amountPaid ?? 0) * 100);
            return sum + minor;
        }, 0);
        return {
            metric,
            period,
            value: total / 100,
            currencySymbol,
            unit: "amount",
            source: "sales",
            lastUpdatedIso: nowIso,
        };
    }
    if (metric === "recent_sales") {
        return {
            metric,
            period,
            value: sales.length,
            currencySymbol,
            unit: "sales",
            source: "sales",
            lastUpdatedIso: nowIso,
            details: sales.slice(0, 5).map((doc) => {
                const data = doc.data();
                const total = data.totalMinor ??
                    Math.round((data.total ?? 0) * 100);
                return `${data.receiptNumber ?? doc.id}: ${currencySymbol} ${(total / 100).toFixed(2)}`;
            }),
        };
    }
    if (metric === "best_sellers") {
        const counts = new Map();
        for (const doc of sales) {
            const items = doc.data().items ?? [];
            for (const item of items) {
                const name = String(item.name ?? "Item");
                const qty = Number(item.quantity ?? 0);
                counts.set(name, (counts.get(name) ?? 0) + qty);
            }
        }
        const ranked = [...counts.entries()]
            .sort((a, b) => b[1] - a[1])
            .slice(0, 5);
        return {
            metric,
            period,
            value: ranked[0]?.[1] ?? 0,
            currencySymbol,
            unit: "units",
            source: "sales",
            lastUpdatedIso: nowIso,
            details: ranked.map(([name, qty]) => `${name}: ${qty}`),
        };
    }
    // Default: sales_total
    const totalMinor = sales.reduce((sum, doc) => {
        const data = doc.data();
        const minor = data.totalMinor ??
            Math.round((data.total ?? 0) * 100);
        return sum + minor;
    }, 0);
    return {
        metric: "sales_total",
        period,
        value: totalMinor / 100,
        currencySymbol,
        unit: "amount",
        source: "sales",
        lastUpdatedIso: nowIso,
    };
}
exports.answerSabiBusinessQuestion = (0, https_1.onCall)({
    region: "us-central1",
    secrets: [secrets_1.groqApiKey, secrets_1.groqModel],
    enforceAppCheck: false,
    timeoutSeconds: 45,
}, async (request) => {
    const uid = await (0, businessAuthorization_1.requireAuthenticatedUid)(request.auth?.uid);
    const parsed = schemas_1.businessQuestionRequestSchema.safeParse(request.data);
    if (!parsed.success) {
        throw (0, errors_1.invalidArgument)("Please ask a clearer business question.");
    }
    const { businessId, question } = parsed.data;
    await (0, businessAuthorization_1.requireBusinessMember)(uid, businessId);
    await (0, rateLimiter_1.enforceRateLimit)({
        uid,
        businessId,
        operation: "answerSabiBusinessQuestion",
        windowSeconds: 60,
        maxPerWindow: 15,
        dailyMax: 300,
    });
    const detected = detectMetric(question);
    if (detected.metric === "unknown") {
        return {
            verified: false,
            answer: "I couldn’t verify that from your business records. Try asking about today’s sales, low stock, or customer balances.",
            metric: null,
        };
    }
    const verified = await loadVerifiedMetric(businessId, detected.metric, detected.period);
    const apiKey = secrets_1.groqApiKey.value();
    const model = secrets_1.groqModel.value() || "llama-3.3-70b-versatile";
    let answer = verified.unit === "amount"
        ? `${verified.currencySymbol} ${Number(verified.value).toFixed(2)} for ${verified.period}.`
        : `${verified.value} ${verified.unit} for ${verified.period}.`;
    if (apiKey) {
        try {
            const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
                method: "POST",
                headers: {
                    Authorization: `Bearer ${apiKey}`,
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({
                    model,
                    temperature: 0.2,
                    messages: [
                        { role: "system", content: (0, prompts_1.businessAnswerSystemPrompt)() },
                        {
                            role: "user",
                            content: JSON.stringify({
                                question,
                                verifiedMetric: verified,
                            }),
                        },
                    ],
                }),
            });
            if (response.ok) {
                const body = (await response.json());
                const wording = body.choices?.[0]?.message?.content?.trim();
                if (wording)
                    answer = wording;
            }
        }
        catch {
            // Keep deterministic fallback wording.
        }
    }
    else {
        // Still answer with verified numbers when AI wording is unavailable.
    }
    return {
        verified: true,
        answer,
        metric: verified,
    };
});
//# sourceMappingURL=answerSabiBusinessQuestion.js.map