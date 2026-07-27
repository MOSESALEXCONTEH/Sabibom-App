import {Timestamp} from "firebase-admin/firestore";
import {adminFirestore} from "../config/firebase-admin";
import {periodBounds, periodLabel} from "../utils/date-range";

export type VerifiedMetric = {
  metric: string;
  period: string;
  periodLabel: string;
  value: number | string;
  valueMinor?: number;
  currencyCode: string;
  currencySymbol: string;
  unit: string;
  source: string;
  recordCount: number;
  lastUpdatedIso: string;
  details?: string[];
  startIso: string;
  endIso: string;
};

export function detectMetric(question: string): {
  metric: string;
  period: string;
} {
  const q = question.toLowerCase();
  const mentionsYesterday = q.includes("yesterday");
  const mentionsToday = q.includes("today");
  const mentionsWeek = q.includes("week");
  const mentionsMonth = q.includes("month");
  const period = mentionsYesterday
    ? "yesterday"
    : mentionsWeek
      ? "week"
      : mentionsMonth
        ? "month"
        : mentionsToday
          ? "today"
          : "today";
  const countPeriod =
    mentionsWeek || mentionsMonth || mentionsToday || mentionsYesterday
      ? period
      : "all";
  const asksCount =
    q.includes("how many") ||
    q.includes("number of") ||
    q.includes("count of") ||
    (q.includes("do i have") && !q.includes("owe"));
  const asksLookup =
    q.includes("look") ||
    q.includes("find") ||
    q.includes("check") ||
    q.includes("show") ||
    q.includes("list") ||
    q.includes("which") ||
    q.includes("what") ||
    q.includes("any ");

  // Supplier balances before generic "owe"/balance (customers).
  if (
    q.includes("supplier") &&
    (q.includes("owe") ||
      q.includes("debt") ||
      q.includes("balance") ||
      q.includes("i owe"))
  ) {
    return {metric: "supplier_balances", period: "all"};
  }
  if (
    q.includes("who owes") ||
    q.includes("customer debt") ||
    q.includes("owes me") ||
    (q.includes("customer") &&
      (q.includes("owe") || q.includes("balance") || q.includes("debt"))) ||
    (q.includes("owe") && !q.includes("supplier")) ||
    (q.includes("balance") && q.includes("customer")) ||
    (q.includes("credit") && q.includes("who"))
  ) {
    return {metric: "customer_balances", period: "all"};
  }
  if (q.includes("credit") && (q.includes("create") || q.includes("today"))) {
    return {metric: "credit_created", period};
  }
  if (
    q.includes("low stock") ||
    q.includes("low in stock") ||
    q.includes("out of stock") ||
    q.includes("running low") ||
    (asksLookup &&
      q.includes("stock") &&
      !q.includes("value") &&
      (q.includes("low") || q.includes("out of") || q.includes("running")))
  ) {
    return {metric: "low_stock", period: "all"};
  }

  // Expiry / shelf-life lookups — answer from product records, not UI tips.
  const expiryAsk =
    q.includes("expir") ||
    q.includes("shelf life") ||
    q.includes("shelf-life") ||
    q.includes("best before") ||
    q.includes("going bad") ||
    q.includes("spoil") ||
    q.includes("near date") ||
    q.includes("use by") ||
    q.includes("use-by");
  if (expiryAsk) {
    if (q.includes("expired") && !q.includes("expiring")) {
      return {metric: "expired_products", period: "all"};
    }
    return {metric: "products_expiring", period: "all"};
  }

  if (
    q.includes("potential profit") ||
    q.includes("profit remain") ||
    q.includes("remaining profit") ||
    (q.includes("profit") &&
      (q.includes("left") || q.includes("stock") || q.includes("product")))
  ) {
    return {metric: "product_potential_profit", period: "all"};
  }
  if (
    q.includes("best selling") ||
    q.includes("top selling") ||
    q.includes("best-selling") ||
    (q.includes("best") && q.includes("sell"))
  ) {
    return {metric: "best_sellers", period};
  }
  if (q.includes("recent sales") || q.includes("latest sales")) {
    return {metric: "recent_sales", period};
  }
  if (q.includes("cash") && (q.includes("paid") || q.includes("sale") || q.includes("today"))) {
    return {metric: "cash_paid", period};
  }

  if (
    (q.includes("profit") &&
      (q.includes("left") ||
        q.includes("remaining") ||
        q.includes("potential") ||
        q.includes("stock"))) ||
    q.includes("expected revenue")
  ) {
    return {metric: "inventory_profit_opportunity", period: "all"};
  }
  if (
    q.includes("highest profit") ||
    q.includes("most profit") ||
    q.includes("top profit")
  ) {
    return {metric: "highest_product_profit", period};
  }
  if (q.includes("loss") && q.includes("product")) {
    return {metric: "products_at_loss", period: "all"};
  }
  if (
    q.includes("profit") ||
    q.includes("gross profit") ||
    q.includes("net profit")
  ) {
    return {metric: "net_profit", period};
  }
  if (
    q.includes("expense") ||
    q.includes("spent") ||
    q.includes("spending") ||
    (q.includes("how much") && (q.includes("spend") || q.includes("spent"))) ||
    q.includes("this week's expenses") ||
    q.includes("today's expenses")
  ) {
    return {metric: "expense_total", period};
  }
  if (
    q.includes("stock value") ||
    q.includes("value of my stock") ||
    q.includes("inventory value")
  ) {
    return {metric: "stock_value", period: "all"};
  }

  // Customer count before the generic "how many" sales rule.
  if (asksCount && (q.includes("customer") || q.includes("client"))) {
    return {metric: "customer_count", period: "all"};
  }
  if (
    asksCount &&
    (q.includes("product") || q.includes("item")) &&
    !q.includes("sale")
  ) {
    return {metric: "product_count", period: "all"};
  }
  if (
    q.includes("number of sales") ||
    q.includes("orders") ||
    (asksCount &&
      (q.includes("sale") || q.includes("order") || q.includes("receipt")))
  ) {
    return {metric: "sales_count", period: countPeriod};
  }
  if (
    q.includes("this week's sales") ||
    q.includes("today's sales") ||
    q.includes("yesterday's sales") ||
    ((q.includes("sell") || q.includes("sold") || q.includes("sales") || q.includes("revenue")) &&
      (mentionsToday ||
        mentionsWeek ||
        mentionsMonth ||
        mentionsYesterday ||
        q.includes("how much") ||
        q.includes("total") ||
        q.includes("did i") ||
        q.includes("have i")))
  ) {
    return {metric: "sales_total", period};
  }
  if (q.includes("sell") || q.includes("sales") || q.includes("revenue")) {
    return {metric: "sales_total", period};
  }

  // Soft fallbacks — only when stock/low or debt keywords appear.
  if (
    asksLookup &&
    (q.includes("product") || q.includes("item")) &&
    (q.includes("low") || q.includes("stock") || q.includes("out"))
  ) {
    return {metric: "low_stock", period: "all"};
  }
  if (
    asksLookup &&
    (q.includes("customer") || q.includes("client")) &&
    (q.includes("owe") || q.includes("debt") || q.includes("balance"))
  ) {
    return {metric: "customer_balances", period: "all"};
  }

  return {metric: "unknown", period};
}

function isCompletedSale(data: Record<string, unknown>): boolean {
  const saleStatus =
    typeof data.saleStatus === "string"
      ? data.saleStatus
      : typeof data.status === "string"
        ? data.status
        : "completed";
  return saleStatus === "completed";
}

export async function loadVerifiedMetric(
  businessId: string,
  metric: string,
  period: string,
): Promise<VerifiedMetric> {
  const db = adminFirestore();
  const businessRef = db.collection("businesses").doc(businessId);
  const businessSnap = await businessRef.get();
  const business = businessSnap.data() ?? {};
  const currencySymbol =
    (business.currencySymbol as string | undefined) ?? "Le";
  const currencyCode = (business.currencyCode as string | undefined) ?? "SLE";
  const nowIso = new Date().toISOString();

  if (metric === "low_stock") {
    const products = await businessRef.collection("products").limit(200).get();
    const low = products.docs.filter((doc) => {
      const data = doc.data();
      const track = data.trackStock !== false;
      const status = (data.status as string | undefined) ?? "active";
      if (!track || status !== "active") return false;
      const qty = (data.quantity as number | undefined) ?? 0;
      const threshold = (data.lowStockThreshold as number | undefined) ?? 0;
      return qty <= threshold;
    });
    return {
      metric,
      period: "all",
      periodLabel: periodLabel("all"),
      value: low.length,
      currencyCode,
      currencySymbol,
      unit: "products",
      source: "products",
      recordCount: low.length,
      lastUpdatedIso: nowIso,
      details: low.slice(0, 5).map((doc) => {
        const data = doc.data();
        return `${data.name ?? "Product"} (${data.quantity ?? 0})`;
      }),
      startIso: "",
      endIso: nowIso,
    };
  }

  if (metric === "products_expiring") {
    const products = await businessRef.collection("products").limit(300).get();
    const attention = products.docs
      .map((doc) => {
        const data = doc.data();
        const status = (data.status as string | undefined) ?? "active";
        if (status !== "active" || data.tracksExpiry !== true) return null;
        const expiryStatus = String(data.expiryStatus ?? "not_tracked");
        const expiringQty = Number(data.expiringQuantity ?? 0);
        const expiredQty = Number(data.expiredQuantity ?? 0);
        const relevant =
          expiryStatus === "expiring_soon" ||
          expiryStatus === "expires_today" ||
          expiryStatus === "expired" ||
          expiryStatus === "mixed" ||
          expiringQty > 0 ||
          expiredQty > 0;
        if (!relevant) return null;
        return {
          name: String(data.name ?? "Product"),
          expiryStatus,
          expiringQty,
          expiredQty,
        };
      })
      .filter((row): row is NonNullable<typeof row> => row != null);
    return {
      metric,
      period: "all",
      periodLabel: periodLabel("all"),
      value: attention.length,
      currencyCode,
      currencySymbol,
      unit: "products",
      source: "products",
      recordCount: attention.length,
      lastUpdatedIso: nowIso,
      details: attention.slice(0, 8).map((row) => {
        const parts = [row.name, row.expiryStatus.replaceAll("_", " ")];
        if (row.expiredQty > 0) parts.push(`expired ${row.expiredQty}`);
        if (row.expiringQty > 0) parts.push(`expiring ${row.expiringQty}`);
        return parts.join(" · ");
      }),
      startIso: "",
      endIso: nowIso,
    };
  }

  if (metric === "product_potential_profit") {
    const products = await businessRef.collection("products").limit(400).get();
    const rows = products.docs
      .map((doc) => {
        const data = doc.data();
        const status = (data.status as string | undefined) ?? "active";
        if (status !== "active") return null;
        const potential =
          (data.potentialProfitRemainingMinor as number | undefined) ??
          Math.round(
            Number(data.quantity ?? 0) *
              (((data.sellingPriceMinor as number | undefined) ?? 0) -
                ((data.costPriceMinor as number | undefined) ?? 0)),
          );
        return {
          name: String(data.name ?? "Product"),
          potential,
        };
      })
      .filter((row): row is NonNullable<typeof row> => row != null)
      .sort((a, b) => b.potential - a.potential);
    const total = rows.reduce((sum, row) => sum + row.potential, 0);
    return {
      metric,
      period: "all",
      periodLabel: periodLabel("all"),
      value: total / 100,
      valueMinor: total,
      currencyCode,
      currencySymbol,
      unit: "amount",
      source: "products",
      recordCount: rows.length,
      lastUpdatedIso: nowIso,
      details: rows
        .slice(0, 5)
        .map(
          (row) =>
            `${row.name}: ${currencySymbol} ${(row.potential / 100).toFixed(2)}`,
        ),
      startIso: "",
      endIso: nowIso,
    };
  }

  if (
    metric === "expiring_products" ||
    metric === "expired_products" ||
    metric === "inventory_profit_opportunity" ||
    metric === "highest_product_profit" ||
    metric === "products_at_loss"
  ) {
    const products = await businessRef.collection("products").limit(300).get();
    const active = products.docs.filter((doc) => {
      const status = (doc.data().status as string | undefined) ?? "active";
      return status === "active";
    });

    if (metric === "expiring_products" || metric === "expired_products") {
      const matched = active.filter((doc) => {
        const data = doc.data();
        if (data.tracksExpiry !== true) return false;
        const status = String(data.expiryStatus ?? "not_tracked");
        const expiredQty = Number(data.expiredQuantity ?? 0);
        const expiringQty = Number(data.expiringQuantity ?? 0);
        if (metric === "expired_products") {
          return expiredQty > 0 || status === "expired";
        }
        return (
          status === "expiring_soon" ||
          status === "expires_today" ||
          expiringQty > 0
        );
      });
      return {
        metric,
        period: "all",
        periodLabel: periodLabel("all"),
        value: matched.length,
        currencyCode,
        currencySymbol,
        unit: "products",
        source: "products",
        recordCount: matched.length,
        lastUpdatedIso: nowIso,
        details: matched.slice(0, 8).map((doc) => {
          const data = doc.data();
          const next = data.nextExpiryDate;
          const date =
            next instanceof Timestamp
              ? next.toDate().toISOString().slice(0, 10)
              : typeof next === "string"
                ? next.slice(0, 10)
                : "unknown";
          return `${data.name ?? "Product"} · ${data.expiryStatus ?? "tracked"} · ${date}`;
        }),
        startIso: "",
        endIso: nowIso,
      };
    }

    if (metric === "inventory_profit_opportunity") {
      let stockCost = 0;
      let expectedRevenue = 0;
      let potential = 0;
      for (const doc of active) {
        const data = doc.data();
        stockCost += Math.round(Number(data.stockCostValueMinor ?? 0));
        expectedRevenue += Math.round(
          Number(data.expectedStockRevenueMinor ?? 0),
        );
        potential += Math.round(
          Number(data.potentialProfitRemainingMinor ?? 0),
        );
      }
      return {
        metric,
        period: "all",
        periodLabel: "Current stock estimate",
        value: potential / 100,
        valueMinor: potential,
        currencyCode,
        currencySymbol,
        unit: "money",
        source: "products",
        recordCount: active.length,
        lastUpdatedIso: nowIso,
        details: [
          `Stock cost ${currencySymbol} ${(stockCost / 100).toFixed(2)}`,
          `Expected revenue ${currencySymbol} ${(expectedRevenue / 100).toFixed(2)}`,
          `Estimated profit remaining ${currencySymbol} ${(potential / 100).toFixed(2)}`,
          "These values are current stock estimates, not guaranteed profit.",
        ],
        startIso: "",
        endIso: nowIso,
      };
    }

    const ranked = active
      .map((doc) => {
        const data = doc.data();
        return {
          name: String(data.name ?? "Product"),
          realized: Math.round(Number(data.realizedGrossProfitMinor ?? 0)),
          potential: Math.round(
            Number(data.potentialProfitRemainingMinor ?? 0),
          ),
        };
      })
      .sort((a, b) =>
        metric === "products_at_loss"
          ? a.potential - b.potential
          : b.realized - a.realized,
      );
    const rows =
      metric === "products_at_loss"
        ? ranked.filter((row) => row.potential < 0).slice(0, 8)
        : ranked.slice(0, 8);
    return {
      metric,
      period,
      periodLabel: periodLabel(period),
      value: rows.length,
      currencyCode,
      currencySymbol,
      unit: "products",
      source: "products",
      recordCount: rows.length,
      lastUpdatedIso: nowIso,
      details: rows.map((row) =>
        metric === "products_at_loss"
          ? `${row.name} · potential ${currencySymbol} ${(row.potential / 100).toFixed(2)}`
          : `${row.name} · made ${currencySymbol} ${(row.realized / 100).toFixed(2)}`,
      ),
      startIso: "",
      endIso: nowIso,
    };
  }

  if (metric === "customer_balances") {
    const customers = await businessRef.collection("customers").limit(200).get();
    const owing = customers.docs
      .map((doc) => {
        const data = doc.data();
        const balanceMinor =
          (data.balanceMinor as number | undefined) ??
          Math.round(((data.balance as number | undefined) ?? 0) * 100);
        return {
          name: (data.name as string | undefined) ?? "Customer",
          balanceMinor,
        };
      })
      .filter((row) => row.balanceMinor > 0)
      .sort((a, b) => b.balanceMinor - a.balanceMinor);
    const totalMinor = owing.reduce((sum, row) => sum + row.balanceMinor, 0);
    return {
      metric,
      period: "all",
      periodLabel: periodLabel("all"),
      value: totalMinor / 100,
      valueMinor: totalMinor,
      currencyCode,
      currencySymbol,
      unit: "amount",
      source: "customers",
      recordCount: owing.length,
      lastUpdatedIso: nowIso,
      details: owing
        .slice(0, 5)
        .map(
          (row) =>
            `${row.name}: ${currencySymbol} ${(row.balanceMinor / 100).toFixed(2)}`,
        ),
      startIso: "",
      endIso: nowIso,
    };
  }

  if (metric === "customer_count") {
    const customers = await businessRef.collection("customers").limit(500).get();
    const active = customers.docs.filter((doc) => {
      const status = (doc.data().status as string | undefined) ?? "active";
      return status !== "archived" && status !== "deleted";
    });
    return {
      metric,
      period: "all",
      periodLabel: periodLabel("all"),
      value: active.length,
      currencyCode,
      currencySymbol,
      unit: "customers",
      source: "customers",
      recordCount: active.length,
      lastUpdatedIso: nowIso,
      startIso: "",
      endIso: nowIso,
    };
  }

  if (metric === "product_count") {
    const products = await businessRef.collection("products").limit(500).get();
    const active = products.docs.filter((doc) => {
      const status = (doc.data().status as string | undefined) ?? "active";
      return status === "active";
    });
    return {
      metric,
      period: "all",
      periodLabel: periodLabel("all"),
      value: active.length,
      currencyCode,
      currencySymbol,
      unit: "products",
      source: "products",
      recordCount: active.length,
      lastUpdatedIso: nowIso,
      startIso: "",
      endIso: nowIso,
    };
  }

  if (metric === "supplier_balances") {
    const suppliers = await businessRef.collection("suppliers").limit(300).get();
    const owing = suppliers.docs
      .map((doc) => {
        const data = doc.data();
        const balanceMinor =
          (data.balanceMinor as number | undefined) ??
          Math.round(((data.balance as number | undefined) ?? 0) * 100);
        return {
          name: (data.name as string | undefined) ?? "Supplier",
          balanceMinor,
          status: (data.status as string | undefined) ?? "active",
        };
      })
      .filter((row) => row.status !== "archived" && row.balanceMinor > 0)
      .sort((a, b) => b.balanceMinor - a.balanceMinor);
    const total = owing.reduce((sum, row) => sum + row.balanceMinor, 0);
    return {
      metric,
      period: "all",
      periodLabel: periodLabel("all"),
      value: total / 100,
      valueMinor: total,
      currencyCode,
      currencySymbol,
      unit: "amount",
      source: "suppliers",
      recordCount: owing.length,
      lastUpdatedIso: nowIso,
      details: owing
        .slice(0, 5)
        .map(
          (row) =>
            `${row.name}: ${currencySymbol} ${(row.balanceMinor / 100).toFixed(2)}`,
        ),
      startIso: "",
      endIso: nowIso,
    };
  }

  if (metric === "stock_value") {
    const products = await businessRef.collection("products").limit(500).get();
    let total = 0;
    let counted = 0;
    for (const doc of products.docs) {
      const data = doc.data();
      const status = (data.status as string | undefined) ?? "active";
      const trackStock = (data.trackStock as boolean | undefined) ?? true;
      if (status !== "active" || !trackStock) continue;
      const qty = Number(data.quantity ?? 0);
      const costMinor =
        (data.costPriceMinor as number | undefined) ??
        Math.round(((data.costPrice as number | undefined) ?? 0) * 100);
      total += Math.round(qty * costMinor);
      counted += 1;
    }
    return {
      metric,
      period: "all",
      periodLabel: periodLabel("all"),
      value: total / 100,
      valueMinor: total,
      currencyCode,
      currencySymbol,
      unit: "amount",
      source: "products",
      recordCount: counted,
      lastUpdatedIso: nowIso,
      startIso: "",
      endIso: nowIso,
    };
  }

  const {start, end} = periodBounds(period);
  const salesSnap = await businessRef
    .collection("sales")
    .where("createdAt", ">=", Timestamp.fromDate(start))
    .where("createdAt", "<", Timestamp.fromDate(end))
    .limit(300)
    .get();

  const sales = salesSnap.docs.filter((doc) =>
    isCompletedSale(doc.data() as Record<string, unknown>),
  );

  if (metric === "sales_count") {
    return {
      metric,
      period,
      periodLabel: periodLabel(period),
      value: sales.length,
      currencyCode,
      currencySymbol,
      unit: "sales",
      source: "sales",
      recordCount: sales.length,
      lastUpdatedIso: nowIso,
      startIso: start.toISOString(),
      endIso: end.toISOString(),
    };
  }

  if (metric === "cash_paid") {
    const cash = sales.filter(
      (doc) => (doc.data().paymentMethod as string | undefined) === "cash",
    );
    const total = cash.reduce((sum, doc) => {
      const data = doc.data();
      const minor =
        (data.amountPaidMinor as number | undefined) ??
        Math.round(((data.amountPaid as number | undefined) ?? 0) * 100);
      return sum + minor;
    }, 0);
    return {
      metric,
      period,
      periodLabel: periodLabel(period),
      value: total / 100,
      valueMinor: total,
      currencyCode,
      currencySymbol,
      unit: "amount",
      source: "sales",
      recordCount: cash.length,
      lastUpdatedIso: nowIso,
      startIso: start.toISOString(),
      endIso: end.toISOString(),
    };
  }

  if (metric === "credit_created") {
    const credit = sales.filter((doc) => {
      const data = doc.data();
      const balance =
        (data.balanceDueMinor as number | undefined) ?? 0;
      return balance > 0;
    });
    const total = credit.reduce((sum, doc) => {
      return sum + ((doc.data().balanceDueMinor as number | undefined) ?? 0);
    }, 0);
    return {
      metric,
      period,
      periodLabel: periodLabel(period),
      value: total / 100,
      valueMinor: total,
      currencyCode,
      currencySymbol,
      unit: "amount",
      source: "sales",
      recordCount: credit.length,
      lastUpdatedIso: nowIso,
      startIso: start.toISOString(),
      endIso: end.toISOString(),
    };
  }

  if (metric === "recent_sales") {
    return {
      metric,
      period,
      periodLabel: periodLabel(period),
      value: sales.length,
      currencyCode,
      currencySymbol,
      unit: "sales",
      source: "sales",
      recordCount: sales.length,
      lastUpdatedIso: nowIso,
      details: sales.slice(0, 5).map((doc) => {
        const data = doc.data();
        const total =
          (data.totalMinor as number | undefined) ??
          Math.round(((data.total as number | undefined) ?? 0) * 100);
        return `${data.receiptNumber ?? doc.id}: ${currencySymbol} ${(total / 100).toFixed(2)}`;
      }),
      startIso: start.toISOString(),
      endIso: end.toISOString(),
    };
  }

  if (metric === "best_sellers") {
    const counts = new Map<string, number>();
    for (const doc of sales) {
      const items = (doc.data().items as Array<Record<string, unknown>>) ?? [];
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
      periodLabel: periodLabel(period),
      value: ranked[0]?.[1] ?? 0,
      currencyCode,
      currencySymbol,
      unit: "units",
      source: "sales",
      recordCount: ranked.length,
      lastUpdatedIso: nowIso,
      details: ranked.map(([name, qty]) => `${name}: ${qty}`),
      startIso: start.toISOString(),
      endIso: end.toISOString(),
    };
  }

  if (metric === "expense_total" || metric === "net_profit") {
    const expensesSnap = await businessRef
      .collection("expenses")
      .where("expenseDate", ">=", Timestamp.fromDate(start))
      .where("expenseDate", "<", Timestamp.fromDate(end))
      .limit(300)
      .get();
    const expenses = expensesSnap.docs.filter((doc) => {
      const status = (doc.data().status as string | undefined) ?? "active";
      return status !== "voided" && status !== "cancelled";
    });
    const expenseMinor = expenses.reduce((sum, doc) => {
      const data = doc.data();
      return (
        sum +
        ((data.amountMinor as number | undefined) ??
          Math.round(((data.amount as number | undefined) ?? 0) * 100))
      );
    }, 0);

    if (metric === "expense_total") {
      return {
        metric,
        period,
        periodLabel: periodLabel(period),
        value: expenseMinor / 100,
        valueMinor: expenseMinor,
        currencyCode,
        currencySymbol,
        unit: "amount",
        source: "expenses",
        recordCount: expenses.length,
        lastUpdatedIso: nowIso,
        startIso: start.toISOString(),
        endIso: end.toISOString(),
      };
    }

    let cogsMinor = 0;
    let missingCost = false;
    for (const doc of sales) {
      const items = (doc.data().items as Array<Record<string, unknown>>) ?? [];
      for (const item of items) {
        const qty = Number(item.quantity ?? 0);
        const cost = item.costPriceMinor;
        if (typeof cost !== "number") {
          missingCost = true;
          continue;
        }
        cogsMinor += Math.round(qty * cost);
      }
    }
    const netSalesMinor = sales.reduce((sum, doc) => {
      const data = doc.data();
      return (
        sum +
        ((data.totalMinor as number | undefined) ??
          Math.round(((data.total as number | undefined) ?? 0) * 100))
      );
    }, 0);
    const grossProfit = netSalesMinor - cogsMinor;
    const netProfit = grossProfit - expenseMinor;
    return {
      metric: "net_profit",
      period,
      periodLabel: periodLabel(period),
      value: netProfit / 100,
      valueMinor: netProfit,
      currencyCode,
      currencySymbol,
      unit: "amount",
      source: "sales+expenses",
      recordCount: sales.length + expenses.length,
      lastUpdatedIso: nowIso,
      details: [
        `Net sales: ${currencySymbol} ${(netSalesMinor / 100).toFixed(2)}`,
        `COGS: ${currencySymbol} ${(cogsMinor / 100).toFixed(2)}${missingCost ? " (estimated)" : ""}`,
        `Expenses: ${currencySymbol} ${(expenseMinor / 100).toFixed(2)}`,
        `Gross profit: ${currencySymbol} ${(grossProfit / 100).toFixed(2)}`,
      ],
      startIso: start.toISOString(),
      endIso: end.toISOString(),
    };
  }

  const totalMinor = sales.reduce((sum, doc) => {
    const data = doc.data();
    const minor =
      (data.totalMinor as number | undefined) ??
      Math.round(((data.total as number | undefined) ?? 0) * 100);
    return sum + minor;
  }, 0);

  return {
    metric: "sales_total",
    period,
    periodLabel: periodLabel(period),
    value: totalMinor / 100,
    valueMinor: totalMinor,
    currencyCode,
    currencySymbol,
    unit: "amount",
    source: "sales",
    recordCount: sales.length,
    lastUpdatedIso: nowIso,
    startIso: start.toISOString(),
    endIso: end.toISOString(),
  };
}
