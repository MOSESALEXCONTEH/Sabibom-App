import type {VercelRequest, VercelResponse} from "@vercel/node";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {adminFirestore} from "../../../config/firebase-admin";
import {authenticateRequest} from "../../../middleware/authenticate-request";
import {businessIdSchema} from "../../../schemas/common-schemas";
import {
  calculatePotentialProfit,
  expiryStatusForDate,
} from "../../../services/inventory/product-intelligence";
import {
  assertActiveBranchInTransaction,
  branchInventoryRef,
  requireActiveBranchAccess,
} from "../../../services/inventory/branch-inventory";
import {requireAppPermission} from "../../../services/team/membership-service";
import {errors} from "../../../utils/api-errors";
import {sendSuccess} from "../../../utils/api-response";
import {createHandler, readJsonBody} from "../../../utils/handler";

const initialStockExpiryDateSchema = z
  .string()
  .trim()
  .refine((value) => !Number.isNaN(Date.parse(value)), {
    message: "Invalid expiry date.",
  });

export const createProductSchema = z.object({
  businessId: businessIdSchema,
  branchId: z.string().trim().min(1).max(128),
  productId: z.string().uuid(),
  name: z.string().trim().min(2).max(160),
  sku: z.string().trim().max(80).nullish(),
  barcode: z.string().trim().max(120).nullish(),
  description: z.string().trim().max(2000).nullish(),
  categoryName: z.string().trim().max(120).nullish(),
  sellingPriceMinor: z.number().int().min(0),
  costPriceMinor: z.number().int().min(0),
  trackStock: z.boolean(),
  quantity: z.number().finite().min(0),
  lowStockThreshold: z.number().finite().min(0),
  unit: z.string().trim().min(1).max(80),
  status: z.enum(["active", "archived"]).default("active"),
  tracksExpiry: z.boolean().default(false),
  defaultExpiryReminderDays: z.number().int().min(0).max(365).default(30),
  initialStockExpiryDate: initialStockExpiryDateSchema.nullish(),
  initialStockExpiryDateKnown: z.boolean().default(false),
  imageUrl: z.string().trim().url().max(2048).nullish(),
  imageCid: z.string().trim().max(160).nullish(),
});

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = createProductSchema.safeParse(readJsonBody(req));
    if (!parsed.success) {
      throw errors.invalidArgument("Check the product details and try again.");
    }
    const data = parsed.data;
    await requireAppPermission({
      uid: identity.uid,
      businessId: data.businessId,
      permission: "manage_products",
    });

    if (
      data.initialStockExpiryDateKnown &&
      !data.initialStockExpiryDate
    ) {
      throw errors.invalidArgument("Select a valid expiry date.");
    }
    const quantity = data.trackStock ? data.quantity : 0;
    const expiryKnown =
      data.tracksExpiry &&
      quantity > 0 &&
      data.initialStockExpiryDateKnown &&
      Boolean(data.initialStockExpiryDate);
    const expiryDateOnly = expiryKnown
      ? data.initialStockExpiryDate!.slice(0, 10)
      : null;
    const expiryTimestamp = expiryDateOnly
      ? Timestamp.fromDate(new Date(`${expiryDateOnly}T12:00:00.000Z`))
      : null;

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
    const batchRef = businessRef
      .collection("inventory_batches")
      .doc(`${branchContext.branchId}_${data.productId}_initial`);
    const movementRef = businessRef.collection("inventory_movements").doc();
    const activityRef = businessRef.collection("activity").doc();

    const created = await db.runTransaction(async (transaction) => {
      const [existing, business] = await Promise.all([
        transaction.get(productRef),
        transaction.get(businessRef),
      ]);
      await assertActiveBranchInTransaction({
        transaction,
        branchRef: branchContext.branchRef,
        businessId: data.businessId,
      });
      if (existing.exists) return false;
      const timezone =
        (business.data()?.timezone as string | undefined) ??
        "Africa/Freetown";
      const profit = calculatePotentialProfit({
        quantity,
        unitCostMinor: data.costPriceMinor,
        sellingPriceMinor: data.sellingPriceMinor,
      });
      const expiryStatus = !data.tracksExpiry
        ? "not_tracked"
        : expiryDateOnly
          ? expiryStatusForDate({
              expiryDate: expiryDateOnly,
              reminderThresholdDays: data.defaultExpiryReminderDays,
              timezone,
            })
          : "safe";

      transaction.create(productRef, {
        productId: data.productId,
        businessId: data.businessId,
        name: data.name,
        sku: data.sku || null,
        barcode: data.barcode || null,
        description: data.description || null,
        categoryId: null,
        categoryName: data.categoryName || null,
        sellingPriceMinor: data.sellingPriceMinor,
        costPriceMinor: data.costPriceMinor,
        sellingPrice: data.sellingPriceMinor / 100,
        price: data.sellingPriceMinor / 100,
        costPrice: data.costPriceMinor / 100,
        quantity,
        lowStockThreshold: data.trackStock
          ? data.lowStockThreshold
          : 0,
        trackStock: data.trackStock,
        unit: data.unit,
        imageUrl: data.imageUrl || null,
        imageCid: data.imageCid || null,
        status: data.status,
        tracksExpiry: data.tracksExpiry,
        defaultExpiryReminderDays: data.defaultExpiryReminderDays,
        nextExpiryDate: expiryTimestamp,
        nextExpiryBatchId: expiryDateOnly ? batchRef.id : null,
        nextExpiryBatchQuantity: expiryDateOnly ? quantity : 0,
        expiringQuantity:
          expiryStatus === "expiring_soon" ||
          expiryStatus === "expires_today"
            ? quantity
            : 0,
        expiredQuantity: expiryStatus === "expired" ? quantity : 0,
        unknownExpiryQuantity:
          data.tracksExpiry && quantity > 0 && !expiryKnown ? quantity : 0,
        expiryStatus,
        ...profit,
        realizedGrossProfitMinor: 0,
        profitIsEstimated: false,
        createdBy: identity.uid,
        createdByName: identity.email ?? "Team member",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      transaction.create(inventoryRef, {
        businessId: data.businessId,
        branchId: branchContext.branchId,
        productId: data.productId,
        quantity,
        reservedQuantity: 0,
        availableQuantity: quantity,
        lowStockThreshold: data.trackStock ? data.lowStockThreshold : 0,
        averageUnitCostMinor: data.costPriceMinor,
        stockCostValueMinor: profit.stockCostValueMinor,
        expectedStockRevenueMinor: profit.expectedStockRevenueMinor,
        potentialProfitRemainingMinor: profit.potentialProfitRemainingMinor,
        realizedGrossProfitMinor: 0,
        nextExpiryDate: expiryTimestamp,
        nextExpiryBatchId: expiryDateOnly ? batchRef.id : null,
        nextExpiryBatchQuantity: expiryDateOnly ? quantity : 0,
        expiringQuantity:
          expiryStatus === "expiring_soon" || expiryStatus === "expires_today"
            ? quantity
            : 0,
        expiredQuantity: expiryStatus === "expired" ? quantity : 0,
        unknownExpiryQuantity:
          data.tracksExpiry && quantity > 0 && !expiryKnown ? quantity : 0,
        expiryStatus,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: identity.uid,
      });

      if (data.trackStock && quantity > 0) {
        transaction.create(batchRef, {
          businessId: data.businessId,
          branchId: branchContext.branchId,
          productId: data.productId,
          productName: data.name,
          sku: data.sku || null,
          sourceType: "initial_stock",
          sourceId: data.productId,
          sourceNumber: null,
          quantityReceived: quantity,
          quantityRemaining: quantity,
          unitCostMinor: data.costPriceMinor,
          sellingPriceAtReceiptMinor: data.sellingPriceMinor,
          expiryDate: expiryTimestamp,
          expiryDateKnown: expiryKnown,
          receivedAt: FieldValue.serverTimestamp(),
          status: expiryStatus === "expired" ? "expired" : "active",
          createdBy: identity.uid,
          createdByName: identity.email ?? "Team member",
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          depletedAt: null,
        });
        transaction.create(movementRef, {
          id: movementRef.id,
          businessId: data.businessId,
          branchId: branchContext.branchId,
          productId: data.productId,
          productName: data.name,
          batchId: batchRef.id,
          type: "opening_balance",
          quantityChange: quantity,
          stockBefore: 0,
          stockAfter: quantity,
          reason: "Opening stock",
          note: null,
          referenceType: "initial_stock",
          referenceId: batchRef.id,
          createdBy: identity.uid,
          createdByName: identity.email ?? "Team member",
          createdAt: FieldValue.serverTimestamp(),
        });
      }

      transaction.create(activityRef, {
        activityId: activityRef.id,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        type: "productAdded",
        title: "Product added",
        subtitle: data.name,
        amount: null,
        referenceId: data.productId,
        createdBy: identity.uid,
        createdByName: identity.email ?? "Team member",
        timestamp: FieldValue.serverTimestamp(),
      });
      return true;
    });

    sendSuccess(res, {productId: data.productId, created});
  },
);
