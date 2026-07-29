import type {VercelRequest, VercelResponse} from "@vercel/node";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {adminFirestore} from "../../../config/firebase-admin";
import {authenticateRequest} from "../../../middleware/authenticate-request";
import {businessIdSchema} from "../../../schemas/common-schemas";
import {
  calculatePurchaseTotals,
  lineDiscountMinor,
  lineSubtotalMinor,
  summarizeInventoryBatches,
  type InventoryBatchSummaryInput,
} from "../../../services/inventory/purchase-intelligence";
import {expiryStatusForDate} from "../../../services/inventory/product-intelligence";
import {
  assertActiveBranchInTransaction,
  branchInventoryRef,
  requireActiveBranchAccess,
  requireBranchIdInBody,
} from "../../../services/inventory/branch-inventory";
import {requireAppPermission} from "../../../services/team/membership-service";
import {errors} from "../../../utils/api-errors";
import {sendSuccess} from "../../../utils/api-response";
import {createHandler, readJsonBody} from "../../../utils/handler";

const discountTypeSchema = z.enum(["fixed", "percentage"]);
const expiryDateSchema = z
  .string()
  .trim()
  .max(64)
  .refine(
    (value) =>
      /^\d{4}-\d{2}-\d{2}/.test(value) &&
      Number.isFinite(Date.parse(value)),
    "Invalid expiry date.",
  );

const purchaseItemSchema = z.object({
  purchaseItemId: z.string().trim().min(1).max(128),
  productId: z.string().trim().min(1).max(128),
  name: z.string().trim().min(1).max(160),
  sku: z.string().trim().max(80).nullish(),
  unit: z.string().trim().min(1).max(80).default("unit"),
  quantity: z.number().finite().positive(),
  unitCostMinor: z.number().int().min(0),
  trackStock: z.boolean(),
  discountType: discountTypeSchema.nullish(),
  discountValue: z.number().finite().default(0),
  tracksExpiry: z.boolean().optional(),
  expiryDate: expiryDateSchema.nullish(),
  expiryDateKnown: z.boolean().default(false),
});

export const completePurchaseSchema = z
  .object({
    purchaseId: z.string().uuid(),
    businessId: businessIdSchema,
    branchId: z.string().trim().min(1).max(128),
    branchNameSnapshot: z.string().trim().min(1).max(160),
    branchCodeSnapshot: z.string().trim().min(2).max(12),
    supplierId: z.string().trim().min(1).max(128),
    supplierName: z.string().trim().min(1).max(160),
    items: z.array(purchaseItemSchema).min(1).max(200),
    orderDiscountType: discountTypeSchema.nullish(),
    orderDiscountValue: z.number().finite().default(0),
    taxPercentage: z.number().finite().min(0).max(100).default(0),
    deliveryMinor: z.number().int().min(0).default(0),
    amountPaidMinor: z.number().int().min(0).default(0),
    paymentMethod: z.string().trim().max(80).nullish(),
  })
  .superRefine((data, context) => {
    const ids = new Set<string>();
    for (const [index, item] of data.items.entries()) {
      if (ids.has(item.purchaseItemId)) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["items", index, "purchaseItemId"],
          message: "Purchase item IDs must be unique.",
        });
      }
      ids.add(item.purchaseItemId);
    }
  });

type PurchaseItem = z.infer<typeof purchaseItemSchema>;

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const body = readJsonBody(req);
    requireBranchIdInBody(body);
    const parsed = completePurchaseSchema.safeParse(body);
    if (!parsed.success) {
      throw errors.invalidArgument("Check the purchase details and try again.");
    }
    const data = parsed.data;
    await requireAppPermission({
      uid: identity.uid,
      businessId: data.businessId,
      permission: "create_purchase",
    });

    let totals;
    try {
      totals = calculatePurchaseTotals(data);
    } catch (error) {
      throw errors.invalidArgument(
        error instanceof Error
          ? error.message
          : "Check the purchase details and try again.",
      );
    }

    const db = adminFirestore();
    const branchContext = await requireActiveBranchAccess({
      db,
      uid: identity.uid,
      businessId: data.businessId,
      branchId: data.branchId,
    });
    const businessRef = branchContext.businessRef;
    const purchaseRef = businessRef
      .collection("purchases")
      .doc(data.purchaseId);
    const supplierRef = businessRef
      .collection("suppliers")
      .doc(data.supplierId);
    const counterRef = branchContext.branchRef
      .collection("counters")
      .doc("purchases");
    const activityRef = businessRef.collection("activity").doc();
    const batchRefs = new Map(
      data.items
        .filter((item) => item.trackStock)
        .map((item) => [
          item.purchaseItemId,
          businessRef.collection("inventory_batches").doc(),
        ]),
    );
    const now = new Date();
    const createdByName = identity.email ?? "Team member";

    const result = await db.runTransaction(async (transaction) => {
      const [businessSnapshot, existingPurchase] = await Promise.all([
        transaction.get(businessRef),
        transaction.get(purchaseRef),
      ]);
      await assertActiveBranchInTransaction({
        transaction,
        branchRef: branchContext.branchRef,
        businessId: data.businessId,
      });
      if (existingPurchase.exists) {
        const existing = existingPurchase.data() ?? {};
        if (existing.branchId !== branchContext.branchId) {
          throw errors.invalidArgument(
            "This purchase ID already belongs to another branch.",
          );
        }
        return {
          purchaseId: data.purchaseId,
          businessId: data.businessId,
          branchId: branchContext.branchId,
          branchNameSnapshot:
            (existing.branchNameSnapshot as string | undefined) ??
            branchContext.branchName,
          branchCodeSnapshot:
            (existing.branchCodeSnapshot as string | undefined) ??
            branchContext.branchCode,
          purchaseNumber:
            (existing.purchaseNumber as string | undefined) ??
            data.purchaseId,
          created: false,
        };
      }
      if (!businessSnapshot.exists) {
        throw errors.notFound("The selected business no longer exists.");
      }

      const uniqueProductIds = [...new Set(data.items.map((item) => item.productId))];
      const productRefs = new Map(
        uniqueProductIds.map((productId) => [
          productId,
          businessRef.collection("products").doc(productId),
        ]),
      );
      const inventoryRefs = new Map(
        uniqueProductIds.map((productId) => [
          productId,
          branchInventoryRef(branchContext, productId),
        ]),
      );
      const batchQueries = new Map(
        uniqueProductIds.map((productId) => [
          productId,
          businessRef
            .collection("inventory_batches")
            .where("productId", "==", productId)
            .where("branchId", "==", branchContext.branchId),
        ]),
      );
      const [
        supplierSnapshot,
        counterSnapshot,
        productResults,
        inventoryResults,
        batchResults,
      ] = await Promise.all([
          transaction.get(supplierRef),
          transaction.get(counterRef),
          Promise.all(
            uniqueProductIds.map((productId) =>
              transaction.get(productRefs.get(productId)!),
            ),
          ),
          Promise.all(
            uniqueProductIds.map((productId) =>
              transaction.get(inventoryRefs.get(productId)!),
            ),
          ),
          Promise.all(
            uniqueProductIds.map((productId) =>
              transaction.get(batchQueries.get(productId)!),
            ),
          ),
        ]);

      if (
        !supplierSnapshot.exists ||
        ((supplierSnapshot.data()?.status as string | undefined) ?? "active") !==
          "active"
      ) {
        throw errors.invalidArgument(
          "The selected supplier is no longer active.",
        );
      }

      const products = new Map(
        uniqueProductIds.map((productId, index) => [
          productId,
          productResults[index],
        ]),
      );
      const inventories = new Map(
        uniqueProductIds.map((productId, index) => [
          productId,
          inventoryResults[index],
        ]),
      );
      const existingBatches = new Map(
        uniqueProductIds.map((productId, index) => [
          productId,
          batchResults[index].docs.map((snapshot) =>
            batchSummaryInput(snapshot.id, snapshot.data()),
          ),
        ]),
      );
      for (const item of data.items) {
        const product = products.get(item.productId);
        if (!product?.exists) {
          throw errors.invalidArgument(`${item.name} is no longer available.`);
        }
        validateExpiryInput(item, product.data() ?? {});
      }

      const timezone =
        (businessSnapshot.data()?.timezone as string | undefined) ??
        "Africa/Freetown";
      const dateKey = businessDateKey(now, timezone);
      const nextNumber = Math.trunc(
        numberValue(counterSnapshot.data()?.nextNumber, 1),
      );
      const purchaseNumber = `PUR-${branchContext.branchCode}-${String(nextNumber).padStart(6, "0")}`;
      const paymentStatus =
        totals.balanceDueMinor === 0
          ? "paid"
          : totals.amountPaidMinor === 0
            ? "unpaid"
            : "partiallyPaid";

      const newBatchesByProduct = new Map<
        string,
        InventoryBatchSummaryInput[]
      >();
      const itemMaps = data.items.map((item) => {
        const productData = products.get(item.productId)!.data() ?? {};
        const tracksExpiry = productData.tracksExpiry === true;
        const batchRef = item.trackStock
          ? batchRefs.get(item.purchaseItemId)!
          : null;
        const expiryDateOnly =
          item.expiryDateKnown && item.expiryDate
            ? item.expiryDate.slice(0, 10)
            : null;
        const expiryTimestamp = expiryDateOnly
          ? dateOnlyTimestamp(expiryDateOnly)
          : null;
        const reminderThresholdDays = numberValue(
          productData.defaultExpiryReminderDays,
          30,
        );
        const expiryState = expiryDateOnly
          ? expiryStatusForDate({
              expiryDate: expiryDateOnly,
              reminderThresholdDays,
              timezone,
              now,
            })
          : null;
        if (batchRef) {
          const batch: InventoryBatchSummaryInput = {
            id: batchRef.id,
            quantityRemaining: item.quantity,
            unitCostMinor: item.unitCostMinor,
            expiryDate: expiryDateOnly,
            expiryDateKnown: Boolean(expiryDateOnly),
            status: expiryState === "expired" ? "expired" : "active",
          };
          const productBatches =
            newBatchesByProduct.get(item.productId) ?? [];
          productBatches.push(batch);
          newBatchesByProduct.set(item.productId, productBatches);
          transaction.create(batchRef, {
            businessId: data.businessId,
            branchId: branchContext.branchId,
            productId: item.productId,
            productName: item.name,
            sku: item.sku || null,
            sourceType: "purchase",
            sourceId: data.purchaseId,
            sourceNumber: purchaseNumber,
            purchaseId: data.purchaseId,
            purchaseItemId: item.purchaseItemId,
            quantityReceived: item.quantity,
            quantityRemaining: item.quantity,
            unitCostMinor: item.unitCostMinor,
            sellingPriceAtReceiptMinor: productSellingPrice(productData),
            expiryDate: expiryTimestamp,
            expiryDateKnown: Boolean(expiryDateOnly),
            receivedAt: FieldValue.serverTimestamp(),
            status: batch.status,
            createdBy: identity.uid,
            createdByName,
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
            depletedAt: null,
          });
        }
        const subtotal = lineSubtotalMinor(item);
        const discount = lineDiscountMinor(item);
        return {
          purchaseItemId: item.purchaseItemId,
          productId: item.productId,
          name: item.name,
          sku: item.sku || null,
          unit: item.unit,
          quantity: item.quantity,
          unitCostMinor: item.unitCostMinor,
          trackStock: item.trackStock,
          discountType: item.discountType ?? null,
          discountValue: item.discountValue,
          tracksExpiry,
          expiryDate: expiryTimestamp,
          expiryDateKnown: Boolean(expiryDateOnly),
          inventoryBatchId: batchRef?.id ?? null,
          lineSubtotalMinor: subtotal,
          discountAmountMinor: discount,
          lineTotalMinor: subtotal - discount,
        };
      });

      transaction.set(
        counterRef,
        {
          nextNumber: nextNumber + 1,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      transaction.create(purchaseRef, {
        purchaseId: data.purchaseId,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        branchNameSnapshot: branchContext.branchName,
        branchCodeSnapshot: branchContext.branchCode,
        purchaseNumber,
        supplierId: data.supplierId,
        supplierName: data.supplierName,
        items: itemMaps,
        itemCount: data.items.length,
        subtotalMinor: totals.subtotalMinor,
        discountMinor:
          totals.itemDiscountMinor + totals.orderDiscountMinor,
        taxMinor: totals.taxMinor,
        deliveryMinor: totals.deliveryMinor,
        totalMinor: totals.totalMinor,
        amountPaidMinor: totals.amountPaidMinor,
        balanceDueMinor: totals.balanceDueMinor,
        paymentMethod: data.paymentMethod ?? null,
        paymentStatus,
        status: "completed",
        createdBy: identity.uid,
        createdByName,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      const strategy =
        (businessSnapshot.data()?.costPriceStrategy as string | undefined) ??
        "weighted_average";
      const runningStock = new Map<string, number>();
      const runningCost = new Map<string, number>();
      for (const item of data.items) {
        const product = products.get(item.productId)!;
        const productData = product.data() ?? {};
        const inventoryData = inventories.get(item.productId)?.data() ?? {};
        const before =
          runningStock.get(item.productId) ??
          numberValue(
            inventoryData.quantity,
            branchContext.branchId === "main"
              ? numberValue(productData.quantity, 0)
              : 0,
          );
        const after = before + item.quantity;
        runningStock.set(item.productId, after);
        const currentCost =
          runningCost.get(item.productId) ??
          numberValue(
            inventoryData.averageUnitCostMinor,
            productCostPrice(productData),
          );
        const newCost =
          strategy === "keep"
            ? currentCost
            : strategy === "latest"
              ? item.unitCostMinor
              : after <= 0
                ? item.unitCostMinor
                : Math.round(
                    (before * currentCost +
                      item.quantity * item.unitCostMinor) /
                      after,
                  );
        runningCost.set(item.productId, newCost);

        if (item.trackStock) {
          const movementRef = businessRef
            .collection("inventory_movements")
            .doc();
          transaction.create(movementRef, {
            id: movementRef.id,
            businessId: data.businessId,
            branchId: branchContext.branchId,
            productId: item.productId,
            productName: item.name,
            batchId: batchRefs.get(item.purchaseItemId)!.id,
            type: "stock_in",
            quantityChange: item.quantity,
            stockBefore: before,
            stockAfter: after,
            reason: "Purchase",
            note: purchaseNumber,
            referenceType: "purchase",
            referenceId: data.purchaseId,
            createdBy: identity.uid,
            createdByName,
            createdAt: FieldValue.serverTimestamp(),
          });
        }
      }

      for (const productId of uniqueProductIds) {
        const productData = products.get(productId)!.data() ?? {};
        const productItems = data.items.filter(
          (item) => item.productId === productId,
        );
        const hasTrackedItem = productItems.some((item) => item.trackStock);
        const newCost =
          runningCost.get(productId) ?? productCostPrice(productData);
        const tracksExpiry = productData.tracksExpiry === true;
        const priorBatches = existingBatches.get(productId) ?? [];
        const addedBatches = newBatchesByProduct.get(productId) ?? [];
        const allBatches = [...priorBatches, ...addedBatches];
        const summary = summarizeInventoryBatches({
          tracksExpiry,
          batches: allBatches,
          sellingPriceMinor: productSellingPrice(productData),
          timezone,
          reminderThresholdDays: numberValue(
            productData.defaultExpiryReminderDays,
            30,
          ),
          now,
        });
        const inventorySnapshot = inventories.get(productId)!;
        const inventoryData = inventorySnapshot.data() ?? {};
        const previousQuantity = numberValue(
          inventoryData.quantity,
          branchContext.branchId === "main"
            ? numberValue(productData.quantity, 0)
            : 0,
        );
        const hasCompleteBatchHistory =
          priorBatches.length > 0 || previousQuantity === 0;
        const aggregateQuantity = hasCompleteBatchHistory
          ? allBatches
              .filter(
                (batch) =>
                  batch.quantityRemaining > 0 &&
                  batch.status !== "depleted" &&
                  batch.status !== "voided",
              )
              .reduce(
                (quantity, batch) => quantity + batch.quantityRemaining,
                0,
              )
          : runningStock.get(productId) ?? previousQuantity;
        if (hasTrackedItem) {
          const reservedQuantity = numberValue(
            inventoryData.reservedQuantity,
            0,
          );
          transaction.set(
            inventoryRefs.get(productId)!,
            {
              businessId: data.businessId,
              branchId: branchContext.branchId,
              productId,
              quantity: aggregateQuantity,
              reservedQuantity,
              availableQuantity: Math.max(
                0,
                aggregateQuantity - reservedQuantity,
              ),
              lowStockThreshold: numberValue(
                inventoryData.lowStockThreshold,
                numberValue(productData.lowStockThreshold, 0),
              ),
              averageUnitCostMinor: newCost,
              stockCostValueMinor: summary.stockCostValueMinor,
              expectedStockRevenueMinor: summary.expectedStockRevenueMinor,
              potentialProfitRemainingMinor:
                summary.potentialProfitRemainingMinor,
              realizedGrossProfitMinor: numberValue(
                inventoryData.realizedGrossProfitMinor,
                0,
              ),
              expiryStatus: summary.expiryStatus,
              nextExpiryDate: summary.nextExpiryDate
                ? dateOnlyTimestamp(summary.nextExpiryDate)
                : null,
              nextExpiryBatchId: summary.nextExpiryBatchId,
              nextExpiryBatchQuantity: summary.nextExpiryBatchQuantity,
              expiringQuantity: summary.expiringQuantity,
              expiredQuantity: summary.expiredQuantity,
              unknownExpiryQuantity: summary.unknownExpiryQuantity,
              updatedAt: FieldValue.serverTimestamp(),
              updatedBy: identity.uid,
              ...(inventorySnapshot.exists
                ? {}
                : {createdAt: FieldValue.serverTimestamp()}),
            },
            {merge: true},
          );
        }
        const quantityAdded = productItems
          .filter((item) => item.trackStock)
          .reduce((sum, item) => sum + item.quantity, 0);
        transaction.update(productRefs.get(productId)!, {
          ...(quantityAdded > 0 && branchContext.branchId === "main"
            ? {quantity: FieldValue.increment(quantityAdded)}
            : {}),
          costPriceMinor: newCost,
          costPrice: newCost / 100,
          unitPotentialProfitMinor:
            productSellingPrice(productData) - newCost,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      const previousBalance = minorValue(
        supplierSnapshot.data()?.balanceMinor,
        supplierSnapshot.data()?.balance,
      );
      const updatedBalance = previousBalance + totals.balanceDueMinor;
      transaction.update(supplierRef, {
        balanceMinor: updatedBalance,
        balance: updatedBalance / 100,
        totalPurchasesMinor: FieldValue.increment(totals.totalMinor),
        purchaseCount: FieldValue.increment(1),
        lastPurchaseAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (totals.balanceDueMinor > 0) {
        const ledgerRef = supplierRef.collection("ledger").doc();
        transaction.create(ledgerRef, {
          type: "purchase_credit",
          purchaseId: data.purchaseId,
          purchaseNumber,
          branchId: branchContext.branchId,
          debitMinor: totals.balanceDueMinor,
          creditMinor: 0,
          balanceBeforeMinor: previousBalance,
          balanceAfterMinor: updatedBalance,
          createdBy: identity.uid,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      transaction.create(activityRef, {
        activityId: activityRef.id,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        type: "purchase",
        title: "Purchase completed",
        subtitle: purchaseNumber,
        amountMinor: totals.totalMinor,
        referenceId: data.purchaseId,
        createdBy: identity.uid,
        createdByName,
        timestamp: FieldValue.serverTimestamp(),
      });
      transaction.set(
        businessRef
          .collection("analytics")
          .doc(`daily_${dateKey}_${branchContext.branchId}`),
        {
          dateKey,
          branchId: branchContext.branchId,
          purchaseMinor: FieldValue.increment(totals.totalMinor),
          purchaseCount: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      return {
        purchaseId: data.purchaseId,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        branchNameSnapshot: branchContext.branchName,
        branchCodeSnapshot: branchContext.branchCode,
        purchaseNumber,
        created: true,
      };
    });

    sendSuccess(res, result);
  },
);

function validateExpiryInput(
  item: PurchaseItem,
  product: Record<string, unknown>,
): void {
  const productTracksStock = product.trackStock !== false;
  if (item.trackStock !== productTracksStock) {
    throw errors.invalidArgument(
      `${item.name}'s stock tracking setting has changed. Refresh and try again.`,
    );
  }
  const productTracksExpiry = product.tracksExpiry === true;
  const hasDate = Boolean(item.expiryDate);
  if (!item.trackStock && (item.expiryDateKnown || hasDate)) {
    throw errors.invalidArgument(
      `Expiry details cannot be recorded for untracked stock (${item.name}).`,
    );
  }
  if (!productTracksExpiry && (item.expiryDateKnown || hasDate)) {
    throw errors.invalidArgument(`${item.name} does not track expiry dates.`);
  }
  if (item.expiryDateKnown !== hasDate) {
    throw errors.invalidArgument(
      item.expiryDateKnown
        ? `Select a valid expiry date for ${item.name}.`
        : `Mark the supplied expiry date as known for ${item.name}.`,
    );
  }
}

function batchSummaryInput(
  id: string,
  data: Record<string, unknown>,
): InventoryBatchSummaryInput {
  const timestamp = data.expiryDate;
  const expiryDate =
    timestamp instanceof Timestamp
      ? timestamp.toDate().toISOString().slice(0, 10)
      : typeof timestamp === "string"
        ? timestamp.slice(0, 10)
        : null;
  const rawStatus = String(data.status ?? "active");
  const status: InventoryBatchSummaryInput["status"] =
    rawStatus === "depleted" ||
    rawStatus === "expired" ||
    rawStatus === "voided"
      ? rawStatus
      : "active";
  return {
    id,
    quantityRemaining: numberValue(data.quantityRemaining, 0),
    unitCostMinor: numberValue(data.unitCostMinor, 0),
    expiryDate,
    expiryDateKnown: data.expiryDateKnown === true && Boolean(expiryDate),
    status,
  };
}

function productCostPrice(product: Record<string, unknown>): number {
  if (typeof product.costPriceMinor === "number") {
    return Math.round(product.costPriceMinor);
  }
  return Math.round(numberValue(product.costPrice, 0) * 100);
}

function productSellingPrice(product: Record<string, unknown>): number {
  if (typeof product.sellingPriceMinor === "number") {
    return Math.round(product.sellingPriceMinor);
  }
  return Math.round(
    numberValue(product.sellingPrice ?? product.price, 0) * 100,
  );
}

function minorValue(minor: unknown, major: unknown): number {
  return typeof minor === "number"
    ? Math.round(minor)
    : Math.round(numberValue(major, 0) * 100);
}

function numberValue(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : fallback;
}

function dateOnlyTimestamp(value: string): Timestamp {
  return Timestamp.fromDate(new Date(`${value}T12:00:00.000Z`));
}

function businessDateKey(now: Date, timezone: string): string {
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(now);
    const read = (type: string) =>
      parts.find((part) => part.type === type)?.value ?? "";
    return `${read("year")}${read("month")}${read("day")}`;
  } catch {
    return now.toISOString().slice(0, 10).replaceAll("-", "");
  }
}
