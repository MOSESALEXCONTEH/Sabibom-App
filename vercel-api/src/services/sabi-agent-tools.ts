import type {DocumentData, QueryDocumentSnapshot} from "firebase-admin/firestore";
import {adminFirestore} from "../config/firebase-admin";

export type AgentBranchScope = {
  branchId: string | null;
  isMainBranch: boolean;
};

export function agentRecordMatchesBranch(
  data: DocumentData,
  scope: AgentBranchScope,
): boolean {
  if (scope.branchId === null) return true;
  const recordBranch =
    typeof data.branchId === "string" ? data.branchId.trim() : "";
  if (!recordBranch) return scope.isMainBranch;
  return recordBranch === scope.branchId;
}

function money(minor: number): string {
  return `Le ${(minor / 100).toFixed(2)}`;
}

function active(docs: QueryDocumentSnapshot<DocumentData>[], scope: AgentBranchScope) {
  return docs.filter((doc) => {
    const data = doc.data();
    return (
      agentRecordMatchesBranch(data, scope) &&
      data.status !== "archived" &&
      data.status !== "deleted"
    );
  });
}

export async function runSabiReadTool(input: {
  businessId: string;
  scope: AgentBranchScope;
  tool: string;
  args: Record<string, unknown>;
}): Promise<string | null> {
  const db = adminFirestore();
  const business = db.collection("businesses").doc(input.businessId);

  if (input.tool === "list_customers" || input.tool === "list_suppliers") {
    const collection =
      input.tool === "list_customers" ? "customers" : "suppliers";
    const label = input.tool === "list_customers" ? "customer" : "supplier";
    const snap = await business.collection(collection).limit(300).get();
    const rows = active(snap.docs, input.scope)
      .map((doc) => String(doc.data().name ?? label).trim())
      .filter(Boolean)
      .sort();
    if (rows.length === 0) return `I found no active ${label}s in this view.`;
    return `I found ${rows.length} active ${label}${rows.length === 1 ? "" : "s"}:\n${rows
      .slice(0, 12)
      .map((name) => `• ${name}`)
      .join("\n")}${rows.length > 12 ? `\n…and ${rows.length - 12} more.` : ""}`;
  }

  if (
    input.tool === "list_products" ||
    input.tool === "check_low_stock"
  ) {
    const products = await business.collection("products").limit(400).get();
    const inventory =
      input.scope.branchId === null
        ? await db
            .collectionGroup("inventory")
            .where("businessId", "==", input.businessId)
            .get()
        : await business
            .collection("branches")
            .doc(input.scope.branchId)
            .collection("inventory")
            .get();
    const stock = new Map<string, {quantity: number; threshold: number}>();
    for (const doc of inventory.docs) {
      const data = doc.data();
      const productId = String(data.productId ?? doc.id);
      const previous = stock.get(productId) ?? {quantity: 0, threshold: 0};
      stock.set(productId, {
        quantity: previous.quantity + Number(data.quantity ?? 0),
        threshold: Math.max(
          previous.threshold,
          Number(data.lowStockThreshold ?? 0),
        ),
      });
    }
    const rows = products.docs
      .filter((doc) => (doc.data().status ?? "active") === "active")
      .map((doc) => {
        const data = doc.data();
        const branchStock = stock.get(doc.id);
        if (!branchStock && !input.scope.isMainBranch) return null;
        const quantity = branchStock
          ? branchStock.quantity
          : Number(data.quantity ?? 0);
        const threshold = branchStock
          ? branchStock.threshold
          : Number(data.lowStockThreshold ?? data.reorderLevel ?? 0);
        return {name: String(data.name ?? "Product"), quantity, threshold};
      })
      .filter((row): row is NonNullable<typeof row> => row !== null)
      .filter(
        (row) =>
          input.tool !== "check_low_stock" ||
          row.quantity <= 0 ||
          (row.threshold > 0 && row.quantity <= row.threshold),
      );
    if (rows.length === 0) {
      return input.tool === "check_low_stock"
        ? "I checked this branch and found no low-stock products."
        : "I found no active products in this view.";
    }
    return `${input.tool === "check_low_stock" ? "Low stock" : "Products"} (${rows.length}):\n${rows
      .slice(0, 12)
      .map((row) => `• ${row.name}: ${row.quantity}`)
      .join("\n")}${rows.length > 12 ? `\n…and ${rows.length - 12} more.` : ""}`;
  }

  if (
    input.tool === "sales_report" ||
    input.tool === "profit_report" ||
    input.tool === "end_of_day_report"
  ) {
    const now = new Date();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const period = String(input.args.period ?? "today").toLowerCase();
    if (period.includes("week")) {
      start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
    } else if (period.includes("month")) {
      start.setDate(1);
    }
    const [salesSnap, expenseSnap] = await Promise.all([
      business.collection("sales").limit(500).get(),
      business.collection("expenses").limit(500).get(),
    ]);
    let sales = 0;
    let netSales = 0;
    let paid = 0;
    let credit = 0;
    let cogs = 0;
    for (const doc of salesSnap.docs) {
      const data = doc.data();
      const created = data.createdAt?.toDate?.() as Date | undefined;
      if (
        !agentRecordMatchesBranch(data, input.scope) ||
        !created ||
        created < start ||
        (data.saleStatus ?? data.status ?? "completed") !== "completed"
      ) {
        continue;
      }
      sales += 1;
      netSales += Number(data.totalMinor ?? 0);
      paid += Number(data.amountPaidMinor ?? 0);
      credit += Number(data.balanceDueMinor ?? 0);
      if (Array.isArray(data.items)) {
        for (const item of data.items) {
          cogs += Number(item.quantity ?? 0) * Number(item.costPriceMinor ?? 0);
        }
      }
    }
    let expenses = 0;
    for (const doc of expenseSnap.docs) {
      const data = doc.data();
      const created =
        (data.expenseDate?.toDate?.() as Date | undefined) ??
        (data.createdAt?.toDate?.() as Date | undefined);
      if (
        !agentRecordMatchesBranch(data, input.scope) ||
        !created ||
        created < start ||
        data.status === "voided" ||
        data.status === "cancelled"
      ) {
        continue;
      }
      expenses += Number(data.amountMinor ?? 0);
    }
    const grossProfit = netSales - cogs;
    const netProfit = grossProfit - expenses;
    return [
      `${input.tool === "end_of_day_report" ? "End-of-day" : input.tool === "profit_report" ? "Profit" : "Sales"} report (${period}):`,
      `• Sales: ${sales} totaling ${money(netSales)}`,
      `• Received: ${money(paid)}`,
      `• Credit sales: ${money(credit)}`,
      `• Expenses: ${money(expenses)}`,
      `• Gross profit: ${money(grossProfit)}`,
      `• Net profit: ${money(netProfit)}`,
    ].join("\n");
  }

  return null;
}
