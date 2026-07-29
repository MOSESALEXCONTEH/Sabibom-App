import type {VercelRequest, VercelResponse} from "@vercel/node";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {adminFirestore} from "../../../config/firebase-admin";
import {authenticateRequest} from "../../../middleware/authenticate-request";
import {businessIdSchema} from "../../../schemas/common-schemas";
import {
  summarizeInventoryBatches,
  type InventoryBatchSummaryInput,
} from "../../../services/inventory/purchase-intelligence";
import {
  assertActiveBranchInTransaction,
  branchInventoryRef,
  requireActiveBranchAccess,
} from "../../../services/inventory/branch-inventory";
import {requireAppPermission} from "../../../services/team/membership-service";
import {errors} from "../../../utils/api-errors";
import {sendSuccess} from "../../../utils/api-response";
import {createHandler, readJsonBody} from "../../../utils/handler";

const disposeBatchSchema = z.object({
  businessId: businessIdSchema,
  branchId: z.string().trim().min(1).max(128),
  batchId: z.string().trim().min(1).max(128),
  quantity: z.number().finite().positive(),
  reason: z.string().trim().min(2).max(500),
});

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = disposeBatchSchema.safeParse(readJsonBody(req));
    if (!parsed.success) {
      throw errors.invalidArgument(
        "Check the disposal quantity and reason, then try again.",
      );
    }
    const data = parsed.data;
    await requireAppPermission({
      uid: identity.uid,
      businessId: data.businessId,
      permission: "dispose_expired_stock",
    });

    const db = adminFirestore();
    const branchContext = await requireActiveBranchAccess({
      db, uid: identity.uid, businessId: data.businessId, branchId: data.branchId,
    });
    const businessRef = branchContext.businessRef;
    const batchRef = businessRef
      .collection("inventory_batches")
      .doc(data.batchId);
    const movementRef = businessRef.collection("inventory_movements").doc();
    const activityRef = businessRef.collection("activity").doc();
    const now = new Date();
    const createdByName = identity.email ?? "Team member";

    const result = await db.runTransaction(async (transaction) => {
      const [businessSnapshot, batchSnapshot] = await Promise.all([
        transaction.get(businessRef),
        transaction.get(batchRef),
      ]);
      await assertActiveBranchInTransaction({
        transaction,
        branchRef: branchContext.branchRef,
        businessId: data.businessId,
      });
      if (!businessSnapshot.exists) {
        throw errors.notFound("The selected business no longer exists.");
      }
      if (!batchSnapshot.exists) {
        throw errors.notFound("Batch not found.");
      }

      const batchData = batchSnapshot.data() ?? {};
      if (batchData.branchId !== branchContext.branchId) {
        throw errors.invalidArgument("This batch belongs to another branch.");
      }
      const productId =
        typeof batchData.productId === "string"
          ? batchData.productId.trim()
          : "";
      if (!productId) {
        throw errors.invalidArgument("Batch is missing a product reference.");
      }

      const remaining = numberValue(batchData.quantityRemaining, 0);
      if (data.quantity > remaining) {
        throw errors.invalidArgument(
          "Disposal quantity cannot exceed remaining batch stock.",
        );
      }

      const productRef = businessRef.collection("products").doc(productId);
      const inventoryRef = branchInventoryRef(branchContext, productId);
      const batchesQuery = businessRef
        .collection("inventory_batches")
        .where("productId", "==", productId)
        .where("branchId", "==", branchContext.branchId);
      const [productSnapshot, inventorySnapshot, batchQuerySnapshot] =
        await Promise.all([
          transaction.get(productRef),
          transaction.get(inventoryRef),
          transaction.get(batchesQuery),
        ]);
      if (!productSnapshot.exists) {
        throw errors.notFound("The selected product no longer exists.");
      }

      const productData = productSnapshot.data() ?? {};
      const productName =
        (typeof batchData.productName === "string" &&
          batchData.productName.trim()) ||
        (typeof productData.name === "string" && productData.name.trim()) ||
        "Unnamed product";
      const timezone =
        (businessSnapshot.data()?.timezone as string | undefined) ??
        "Africa/Freetown";
      const tracksExpiry = productData.tracksExpiry === true;
      const inventoryData = inventorySnapshot.data() ?? {};
      const stockBefore = numberValue(
        inventoryData.quantity,
        branchContext.branchId === "main"
          ? numberValue(productData.quantity, 0)
          : 0,
      );
      const quantityRemaining = remaining - data.quantity;
      const batchStatus: InventoryBatchSummaryInput["status"] =
        quantityRemaining <= 0
          ? "depleted"
          : String(batchData.status ?? "active") === "expired"
            ? "expired"
            : "active";

      const workingBatches = batchQuerySnapshot.docs.map((snapshot) => {
        const summary = batchSummaryInput(snapshot.id, snapshot.data());
        if (snapshot.id !== data.batchId) return summary;
        return {
          ...summary,
          quantityRemaining,
          status: batchStatus,
        };
      });

      const stockAfter = tracksExpiry
        ? workingBatches
            .filter(
              (batch) =>
                batch.quantityRemaining > 0 &&
                batch.status !== "depleted" &&
                batch.status !== "voided",
            )
            .reduce((sum, batch) => sum + batch.quantityRemaining, 0)
        : Math.max(0, stockBefore - data.quantity);

      const summaryBatches = tracksExpiry
        ? workingBatches
        : [
            {
              id: `${productId}_aggregate`,
              quantityRemaining: stockAfter,
              unitCostMinor: productCostPrice(productData),
              expiryDate: null,
              expiryDateKnown: false,
              status: "active" as const,
            },
          ];
      const summary = summarizeInventoryBatches({
        tracksExpiry,
        batches: summaryBatches,
        sellingPriceMinor: productSellingPrice(productData),
        timezone,
        reminderThresholdDays: numberValue(
          productData.defaultExpiryReminderDays,
          30,
        ),
        now,
      });

      transaction.update(batchRef, {
        quantityRemaining,
        status: batchStatus,
        depletedAt:
          batchStatus === "depleted" ? FieldValue.serverTimestamp() : null,
        updatedAt: FieldValue.serverTimestamp(),
      });

      transaction.create(movementRef, {
        id: movementRef.id,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        productId,
        productName,
        batchId: data.batchId,
        type: "expired_stock_disposal",
        quantityChange: -data.quantity,
        stockBefore,
        stockAfter,
        reason: data.reason,
        note: null,
        referenceType: "expired_stock_disposal",
        referenceId: data.batchId,
        createdBy: identity.uid,
        createdByName,
        createdAt: FieldValue.serverTimestamp(),
      });

      transaction.set(
        inventoryRef,
        {
          businessId: data.businessId,
          branchId: branchContext.branchId,
          productId,
          quantity: stockAfter,
          reservedQuantity: numberValue(inventoryData.reservedQuantity, 0),
          availableQuantity: Math.max(
            0,
            stockAfter - numberValue(inventoryData.reservedQuantity, 0),
          ),
          lowStockThreshold: numberValue(
            inventoryData.lowStockThreshold,
            numberValue(productData.lowStockThreshold, 0),
          ),
          averageUnitCostMinor: numberValue(
            inventoryData.averageUnitCostMinor,
            productCostPrice(productData),
          ),
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
        },
        {merge: true},
      );
      // Compatibility aggregate only.
      transaction.update(productRef, {
        quantity: FieldValue.increment(-data.quantity),
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: identity.uid,
      });

      transaction.create(activityRef, {
        activityId: activityRef.id,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        type: "expired_stock_disposal",
        title: "Expired stock disposed",
        subtitle: `${productName} · ${data.quantity} · ${data.reason}`,
        amount: null,
        referenceId: data.batchId,
        createdBy: identity.uid,
        createdByName,
        timestamp: FieldValue.serverTimestamp(),
      });

      return {
        batchId: data.batchId,
        productId,
        quantityDisposed: data.quantity,
        quantityRemaining,
        stockAfter,
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
    unitCostMinor: Math.round(numberValue(data.unitCostMinor, 0)),
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
