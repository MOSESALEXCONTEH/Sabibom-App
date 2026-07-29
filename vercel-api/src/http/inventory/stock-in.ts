import type {VercelRequest, VercelResponse} from "@vercel/node";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {adminFirestore} from "../../config/firebase-admin";
import {authenticateRequest} from "../../middleware/authenticate-request";
import {businessIdSchema} from "../../schemas/common-schemas";
import {
  calculatePotentialProfit,
  expiryStatusForDate,
} from "../../services/inventory/product-intelligence";
import {
  summarizeInventoryBatches,
  type InventoryBatchSummaryInput,
} from "../../services/inventory/purchase-intelligence";
import {
  assertActiveBranchInTransaction,
  branchInventoryRef,
  requireActiveBranchAccess,
} from "../../services/inventory/branch-inventory";
import {requireAppPermission} from "../../services/team/membership-service";
import {errors} from "../../utils/api-errors";
import {sendSuccess} from "../../utils/api-response";
import {createHandler, readJsonBody} from "../../utils/handler";

const optionalText = z
  .string()
  .trim()
  .max(500)
  .nullish()
  .transform((value) => (value && value.length > 0 ? value : null));

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

const stockInSchema = z.object({
  businessId: businessIdSchema,
  branchId: z.string().trim().min(1).max(128),
  productId: z.string().trim().min(1).max(128),
  quantity: z.number().finite().positive(),
  unitCostMinor: z.number().int().min(0),
  expiryDate: expiryDateSchema.nullish(),
  expiryDateKnown: z.boolean().default(false),
  reference: optionalText,
  reason: optionalText,
  note: optionalText,
  batchId: z.string().uuid().optional(),
});

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = stockInSchema.safeParse(readJsonBody(req));
    if (!parsed.success) {
      throw errors.invalidArgument("Check the stock-in details and try again.");
    }
    const data = parsed.data;
    await requireAppPermission({
      uid: identity.uid,
      businessId: data.businessId,
      permission: "adjust_stock",
    });

    const db = adminFirestore();
    const branchContext = await requireActiveBranchAccess({
      db,
      uid: identity.uid,
      businessId: data.businessId,
      branchId: data.branchId,
    });
    const businessRef = branchContext.businessRef;
    const productRef = businessRef.collection("products").doc(data.productId);
    const inventoryRef = branchInventoryRef(branchContext, data.productId);
    const batchRef = data.batchId
      ? businessRef.collection("inventory_batches").doc(data.batchId)
      : businessRef.collection("inventory_batches").doc();
    const movementRef = businessRef.collection("inventory_movements").doc();
    const activityRef = businessRef.collection("activity").doc();
    const batchesQuery = businessRef
      .collection("inventory_batches")
      .where("productId", "==", data.productId)
      .where("branchId", "==", branchContext.branchId);
    const now = new Date();
    const createdByName = identity.email ?? "Team member";

    const result = await db.runTransaction(async (transaction) => {
      const [
        businessSnapshot,
        productSnapshot,
        inventorySnapshot,
        existingBatch,
        batchSnapshot,
      ] = await Promise.all([
        transaction.get(businessRef),
        transaction.get(productRef),
        transaction.get(inventoryRef),
        transaction.get(batchRef),
        transaction.get(batchesQuery),
      ]);
      await assertActiveBranchInTransaction({
        transaction,
        branchRef: branchContext.branchRef,
        businessId: data.businessId,
      });

      if (!businessSnapshot.exists) {
        throw errors.notFound("The selected business no longer exists.");
      }
      if (!productSnapshot.exists) {
        throw errors.notFound("The selected product no longer exists.");
      }

      const productData = productSnapshot.data() ?? {};
      if (productData.trackStock === false) {
        throw errors.invalidArgument(
          "Stock tracking is disabled for this product.",
        );
      }

      if (existingBatch.exists) {
        return {
          productId: data.productId,
          batchId: batchRef.id,
          quantityAfter: numberValue(
            inventorySnapshot.data()?.quantity,
            branchContext.branchId === "main"
              ? numberValue(productData.quantity, 0)
              : 0,
          ),
        };
      }

      const tracksExpiry = productData.tracksExpiry === true;
      if (tracksExpiry && data.expiryDateKnown && !data.expiryDate) {
        throw errors.invalidArgument("Select a valid expiry date.");
      }

      const timezone =
        (businessSnapshot.data()?.timezone as string | undefined) ??
        "Africa/Freetown";
      const expiryDateOnly =
        tracksExpiry && data.expiryDateKnown && data.expiryDate
          ? data.expiryDate.slice(0, 10)
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
      const batchStatus: InventoryBatchSummaryInput["status"] =
        expiryState === "expired" ? "expired" : "active";

      const productName =
        (productData.name as string | undefined)?.trim() || "Unnamed product";
      const sku =
        typeof productData.sku === "string" && productData.sku.trim()
          ? productData.sku.trim()
          : null;
      const sellingPriceMinor = productSellingPrice(productData);
      const inventoryData = inventorySnapshot.data() ?? {};
      const before = numberValue(
        inventoryData.quantity,
        branchContext.branchId === "main"
          ? numberValue(productData.quantity, 0)
          : 0,
      );
      const after = before + data.quantity;
      const strategy =
        (businessSnapshot.data()?.costPriceStrategy as string | undefined) ??
        "weighted_average";
      const currentCost = numberValue(
        inventoryData.averageUnitCostMinor,
        productCostPrice(productData),
      );
      const newCost =
        strategy === "keep"
          ? currentCost
          : strategy === "latest"
            ? data.unitCostMinor
            : after <= 0
              ? data.unitCostMinor
              : Math.round(
                  (before * currentCost +
                    data.quantity * data.unitCostMinor) /
                    after,
                );

      const priorBatches = batchSnapshot.docs.map((snapshot) =>
        batchSummaryInput(snapshot.id, snapshot.data()),
      );
      const newBatch: InventoryBatchSummaryInput = {
        id: batchRef.id,
        quantityRemaining: data.quantity,
        unitCostMinor: data.unitCostMinor,
        expiryDate: expiryDateOnly,
        expiryDateKnown: Boolean(expiryDateOnly),
        status: batchStatus,
      };
      const allBatches = [...priorBatches, newBatch];
      const summary = summarizeInventoryBatches({
        tracksExpiry,
        batches: allBatches,
        sellingPriceMinor,
        timezone,
        reminderThresholdDays,
        now,
      });
      const hasCompleteBatchHistory =
        priorBatches.length > 0 || before === 0;
      const quantityAfter = hasCompleteBatchHistory
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
        : after;
      const profit = calculatePotentialProfit({
        quantity: quantityAfter,
        unitCostMinor: newCost,
        sellingPriceMinor,
      });

      transaction.create(batchRef, {
        businessId: data.businessId,
        branchId: branchContext.branchId,
        productId: data.productId,
        productName,
        sku,
        sourceType: "manual_stock_in",
        sourceId: data.reference ?? batchRef.id,
        sourceNumber: data.reference,
        quantityReceived: data.quantity,
        quantityRemaining: data.quantity,
        unitCostMinor: data.unitCostMinor,
        sellingPriceAtReceiptMinor: sellingPriceMinor,
        expiryDate: expiryTimestamp,
        expiryDateKnown: Boolean(expiryDateOnly),
        receivedAt: FieldValue.serverTimestamp(),
        status: batchStatus,
        createdBy: identity.uid,
        createdByName,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        depletedAt: null,
      });

      transaction.create(movementRef, {
        id: movementRef.id,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        productId: data.productId,
        productName,
        batchId: batchRef.id,
        type: "stock_in",
        quantityChange: data.quantity,
        stockBefore: before,
        stockAfter: quantityAfter,
        reason: data.reason ?? "Stock In",
        note: data.note,
        referenceType: "manual_stock_in",
        referenceId: data.reference ?? batchRef.id,
        createdBy: identity.uid,
        createdByName,
        createdAt: FieldValue.serverTimestamp(),
      });

      transaction.set(
        inventoryRef,
        {
          businessId: data.businessId,
          branchId: branchContext.branchId,
          productId: data.productId,
          quantity: quantityAfter,
          reservedQuantity: numberValue(inventoryData.reservedQuantity, 0),
          availableQuantity: Math.max(
            0,
            quantityAfter - numberValue(inventoryData.reservedQuantity, 0),
          ),
          lowStockThreshold: numberValue(
            inventoryData.lowStockThreshold,
            numberValue(productData.lowStockThreshold, 0),
          ),
          averageUnitCostMinor: newCost,
          stockCostValueMinor: summary.stockCostValueMinor,
          expectedStockRevenueMinor: summary.expectedStockRevenueMinor,
          potentialProfitRemainingMinor: summary.potentialProfitRemainingMinor,
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

      // Compatibility aggregate only. Branch inventory is authoritative.
      transaction.update(productRef, {
        quantity: FieldValue.increment(data.quantity),
        costPriceMinor: newCost,
        costPrice: newCost / 100,
        unitPotentialProfitMinor: profit.unitPotentialProfitMinor,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: identity.uid,
      });

      transaction.create(activityRef, {
        activityId: activityRef.id,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        type: "stockAdjustment",
        title: "Stock adjusted",
        subtitle: `${productName} · Stock In`,
        amount: null,
        referenceId: data.productId,
        createdBy: identity.uid,
        createdByName,
        timestamp: FieldValue.serverTimestamp(),
      });

      return {
        productId: data.productId,
        batchId: batchRef.id,
        quantityAfter,
      };
    });

    sendSuccess(res, result);
  },
);

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

function numberValue(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : fallback;
}

function dateOnlyTimestamp(value: string): Timestamp {
  return Timestamp.fromDate(new Date(`${value}T12:00:00.000Z`));
}
