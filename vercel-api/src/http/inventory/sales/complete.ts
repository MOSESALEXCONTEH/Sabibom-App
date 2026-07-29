import type {VercelRequest, VercelResponse} from "@vercel/node";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {adminFirestore} from "../../../config/firebase-admin";
import {authenticateRequest} from "../../../middleware/authenticate-request";
import {businessIdSchema} from "../../../schemas/common-schemas";
import {
  allocateFefo,
  costOfGoodsSoldFromAllocations,
  weightedUnitCostMinor,
  type FefoAllocation,
  type FefoBatchInput,
  InsufficientStockError,
} from "../../../services/inventory/fefo-allocation";
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
import {minorToMajor} from "../../../utils/money";

const discountTypeSchema = z.enum(["fixed", "percentage"]);
const paymentMethodSchema = z.enum([
  "cash",
  "mobile_money",
  "bank_transfer",
  "card",
  "credit",
]);

const saleItemSchema = z.object({
  saleItemId: z.string().trim().min(1).max(128),
  productId: z.string().trim().min(1).max(128).nullish(),
  isCustomItem: z.boolean().default(false),
  name: z.string().trim().min(1).max(160),
  sku: z.string().trim().max(80).nullish(),
  barcode: z.string().trim().max(120).nullish(),
  unit: z.string().trim().min(1).max(80).default("unit"),
  quantity: z.number().finite().positive(),
  quantityInput: z.string().trim().max(80).nullish(),
  unitPriceMinor: z.number().int().min(0),
  unitPriceInput: z.string().trim().max(80).nullish(),
  costPriceMinor: z.number().int().min(0).default(0),
  trackStock: z.boolean(),
  discountType: discountTypeSchema.nullish(),
  discountValue: z.number().finite().default(0),
});

const completeSaleSchema = z
  .object({
    saleId: z.string().uuid(),
    businessId: businessIdSchema,
    branchId: z.string().trim().min(1).max(128),
    branchNameSnapshot: z.string().trim().min(1).max(160),
    branchCodeSnapshot: z.string().trim().min(2).max(12),
    items: z.array(saleItemSchema).min(1).max(200),
    paymentMethod: paymentMethodSchema,
    amountPaidMinor: z.number().int().min(0).default(0),
    customerId: z.string().trim().min(1).max(128).nullish(),
    customerName: z.string().trim().max(160).nullish(),
    customerPhone: z.string().trim().max(40).nullish(),
    orderDiscountType: discountTypeSchema.nullish(),
    orderDiscountValue: z.number().finite().default(0),
    taxEnabled: z.boolean().default(false),
    taxPercentage: z.number().finite().min(0).max(100).default(0),
    note: z.string().trim().max(500).nullish(),
    cashierName: z.string().trim().max(160).nullish(),
  })
  .superRefine((data, context) => {
    const ids = new Set<string>();
    for (const [index, item] of data.items.entries()) {
      if (ids.has(item.saleItemId)) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["items", index, "saleItemId"],
          message: "Sale item IDs must be unique.",
        });
      }
      ids.add(item.saleItemId);
      if (item.trackStock && !item.productId) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["items", index, "productId"],
          message: "Stock-tracked items require a productId.",
        });
      }
    }
  });

type SaleItemInput = z.infer<typeof saleItemSchema>;
type CompleteSaleInput = z.infer<typeof completeSaleSchema>;

interface SaleTotals {
  subtotalMinor: number;
  itemDiscountMinor: number;
  orderDiscountMinor: number;
  taxMinor: number;
  totalMinor: number;
  amountPaidMinor: number;
  balanceDueMinor: number;
  changeMinor: number;
}

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = completeSaleSchema.safeParse(readJsonBody(req));
    if (!parsed.success) {
      throw errors.invalidArgument("Check the sale details and try again.");
    }
    const data = parsed.data;
    await requireAppPermission({
      uid: identity.uid,
      businessId: data.businessId,
      permission: "create_sale",
    });

    let totals: SaleTotals;
    try {
      totals = calculateSaleTotals(data);
    } catch (error) {
      throw errors.invalidArgument(
        error instanceof Error
          ? error.message
          : "Check the sale details and try again.",
      );
    }

    if (data.paymentMethod === "cash" && totals.amountPaidMinor < totals.totalMinor) {
      throw errors.invalidArgument("Cash received must cover the total.");
    }
    if (totals.balanceDueMinor > 0 && !data.customerId) {
      throw errors.invalidArgument(
        "Select a customer for credit or partial payment.",
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
    const saleRef = businessRef.collection("sales").doc(data.saleId);
    const counterRef = branchContext.branchRef
      .collection("counters")
      .doc("sales");
    const activityRef = businessRef.collection("activity").doc();
    const now = new Date();
    const createdByName = data.cashierName?.trim() || identity.email || "Team member";

    const result = await db.runTransaction(async (transaction) => {
      const [businessSnapshot, existingSale] = await Promise.all([
        transaction.get(businessRef),
        transaction.get(saleRef),
      ]);
      await assertActiveBranchInTransaction({
        transaction,
        branchRef: branchContext.branchRef,
        businessId: data.businessId,
      });
      if (existingSale.exists) {
        const existing = existingSale.data() ?? {};
        return {
          saleId: data.saleId,
          receiptNumber:
            (existing.receiptNumber as string | undefined) ?? data.saleId,
          totalMinor: numberValue(existing.totalMinor, totals.totalMinor),
          amountPaidMinor: numberValue(
            existing.amountPaidMinor,
            totals.amountPaidMinor,
          ),
          balanceDueMinor: numberValue(
            existing.balanceDueMinor,
            totals.balanceDueMinor,
          ),
          changeMinor: numberValue(existing.changeMinor, totals.changeMinor),
          paymentMethod:
            (existing.paymentMethod as string | undefined) ??
            data.paymentMethod,
          created: false,
        };
      }
      if (!businessSnapshot.exists) {
        throw errors.notFound("The selected business no longer exists.");
      }

      const businessData = businessSnapshot.data() ?? {};
      const timezone =
        (businessData.timezone as string | undefined) ?? "Africa/Freetown";
      const currencyCode =
        (businessData.currencyCode as string | undefined) ?? "SLE";
      const currencySymbol =
        (businessData.currencySymbol as string | undefined) ?? "Le";

      const trackedProductIds = [
        ...new Set(
          data.items
            .filter((item) => item.trackStock && item.productId)
            .map((item) => item.productId!),
        ),
      ];
      const productRefs = new Map(
        trackedProductIds.map((productId) => [
          productId,
          businessRef.collection("products").doc(productId),
        ]),
      );
      const inventoryRefs = new Map(
        trackedProductIds.map((productId) => [
          productId,
          branchInventoryRef(branchContext, productId),
        ]),
      );
      const batchQueries = new Map(
        trackedProductIds.map((productId) => [
          productId,
          businessRef
            .collection("inventory_batches")
            .where("productId", "==", productId)
            .where("branchId", "==", branchContext.branchId),
        ]),
      );

      const customerRef = data.customerId
        ? businessRef.collection("customers").doc(data.customerId)
        : null;

      const [
        counterSnapshot,
        customerSnapshot,
        productResults,
        inventoryResults,
        batchResults,
      ] = await Promise.all([
          transaction.get(counterRef),
          customerRef ? transaction.get(customerRef) : Promise.resolve(null),
          Promise.all(
            trackedProductIds.map((productId) =>
              transaction.get(productRefs.get(productId)!),
            ),
          ),
          Promise.all(
            trackedProductIds.map((productId) =>
              transaction.get(inventoryRefs.get(productId)!),
            ),
          ),
          Promise.all(
            trackedProductIds.map((productId) =>
              transaction.get(batchQueries.get(productId)!),
            ),
          ),
        ]);

      if (data.customerId) {
        if (!customerSnapshot?.exists) {
          throw errors.invalidArgument(
            "The selected customer no longer exists.",
          );
        }
      }

      const products = new Map(
        trackedProductIds.map((productId, index) => [
          productId,
          productResults[index],
        ]),
      );
      const inventories = new Map(
        trackedProductIds.map((productId, index) => [
          productId,
          inventoryResults[index],
        ]),
      );
      const batchesByProduct = new Map(
        trackedProductIds.map((productId, index) => [
          productId,
          batchResults[index].docs.map((snapshot) => ({
            ref: snapshot.ref,
            data: snapshot.data(),
            summary: batchSummaryInput(snapshot.id, snapshot.data()),
          })),
        ]),
      );

      for (const item of data.items) {
        if (!item.trackStock || !item.productId) continue;
        const product = products.get(item.productId);
        if (!product?.exists) {
          throw errors.invalidArgument(`${item.name} is no longer available.`);
        }
        const productData = product.data() ?? {};
        const inventoryData = inventories.get(item.productId)?.data() ?? {};
        const available = numberValue(
          inventoryData.quantity,
          branchContext.branchId === "main"
            ? numberValue(productData.quantity, 0)
            : 0,
        );
        if (available < item.quantity) {
          throw errors.invalidArgument(
            `Not enough stock for ${item.name}. Only ${available} remaining.`,
          );
        }
      }

      const dateKey = businessDateKey(now, timezone);
      const nextNumber = Math.trunc(
        numberValue(counterSnapshot.data()?.nextNumber, 1),
      );
      const receiptNumber = `${branchContext.branchCode}-${String(nextNumber).padStart(6, "0")}`;
      const paymentStatus =
        totals.balanceDueMinor === 0
          ? "paid"
          : totals.amountPaidMinor === 0
            ? "unpaid"
            : "partiallyPaid";

      const afterItemDiscount = Math.max(
        0,
        totals.subtotalMinor - totals.itemDiscountMinor,
      );
      const mutableBatches = new Map<string, FefoBatchInput[]>();
      for (const productId of trackedProductIds) {
        mutableBatches.set(
          productId,
          (batchesByProduct.get(productId) ?? []).map((row) => ({
            ...row.summary,
          })),
        );
      }

      const productProfitDelta = new Map<string, number>();
      const runningStock = new Map<string, number>();
      const itemMaps: Record<string, unknown>[] = [];
      let saleCogsMinor = 0;
      let saleActualNetRevenueMinor = 0;
      let saleGrossProfitMinor = 0;

      for (const item of data.items) {
        const subtotal = lineSubtotalMinor(item);
        const discount = lineDiscountMinor(item);
        const lineTotalAfterItem = Math.max(0, subtotal - discount);
        const orderShare =
          afterItemDiscount > 0 && totals.orderDiscountMinor > 0
            ? Math.round(
                (lineTotalAfterItem / afterItemDiscount) *
                  totals.orderDiscountMinor,
              )
            : 0;
        const actualNetRevenueMinor = Math.max(
          0,
          lineTotalAfterItem - orderShare,
        );

        let batchAllocations: Array<Record<string, unknown>> = [];
        let costOfGoodsSoldMinor = Math.round(
          item.quantity * item.costPriceMinor,
        );
        let effectiveCostPriceMinor = item.costPriceMinor;
        const productId = item.productId ?? null;
        const productData =
          productId && products.get(productId)?.exists
            ? (products.get(productId)!.data() ?? {})
            : null;
        const tracksExpiry = productData?.tracksExpiry === true;

        if (item.trackStock && productId && productData) {
          const inventoryData = inventories.get(productId)?.data() ?? {};
          const before =
            runningStock.get(productId) ??
            numberValue(
              inventoryData.quantity,
              branchContext.branchId === "main"
                ? numberValue(productData.quantity, 0)
                : 0,
            );
          const after = before - item.quantity;
          runningStock.set(productId, after);

          if (tracksExpiry) {
            const working = mutableBatches.get(productId) ?? [];
            let allocations: FefoAllocation[];
            try {
              allocations = allocateFefo({
                requestedQty: item.quantity,
                batches: working,
                timezone,
                now,
              });
            } catch (error) {
              if (error instanceof InsufficientStockError) {
                throw errors.invalidArgument(
                  `Not enough saleable stock for ${item.name}.`,
                );
              }
              throw error;
            }
            costOfGoodsSoldMinor =
              costOfGoodsSoldFromAllocations(allocations);
            effectiveCostPriceMinor = weightedUnitCostMinor(
              allocations,
              item.quantity,
            );
            batchAllocations = allocations.map((allocation) => ({
              batchId: allocation.batchId,
              quantity: allocation.quantity,
              unitCostMinor: allocation.unitCostMinor,
              expiryDate: allocation.expiryDate
                ? dateOnlyTimestamp(allocation.expiryDate)
                : null,
              lineCostMinor: allocation.lineCostMinor,
            }));

            applyAllocationsToWorkingBatches(working, allocations);
            mutableBatches.set(productId, working);

            for (const allocation of allocations) {
              const batchRow = (batchesByProduct.get(productId) ?? []).find(
                (row) => row.summary.id === allocation.batchId,
              );
              if (!batchRow) continue;
              const current = working.find((b) => b.id === allocation.batchId)!;
              const depleted = current.quantityRemaining <= 1e-9;
              transaction.update(batchRow.ref, {
                quantityRemaining: Math.max(0, current.quantityRemaining),
                status: depleted ? "depleted" : current.status,
                depletedAt: depleted
                  ? FieldValue.serverTimestamp()
                  : null,
                updatedAt: FieldValue.serverTimestamp(),
              });
              const movementRef = businessRef
                .collection("inventory_movements")
                .doc();
              transaction.create(movementRef, {
                id: movementRef.id,
                businessId: data.businessId,
                branchId: branchContext.branchId,
                productId,
                productName: item.name,
                batchId: allocation.batchId,
                type: "stock_out",
                quantityChange: -allocation.quantity,
                stockBefore: before,
                stockAfter: after,
                reason: "Sale",
                note: receiptNumber,
                referenceType: "sale",
                referenceId: data.saleId,
                createdBy: identity.uid,
                createdByName,
                createdAt: FieldValue.serverTimestamp(),
              });
            }
          } else {
            const movementRef = businessRef
              .collection("inventory_movements")
              .doc();
            transaction.create(movementRef, {
              id: movementRef.id,
              businessId: data.businessId,
              branchId: branchContext.branchId,
              productId,
              productName: item.name,
              type: "stock_out",
              quantityChange: -item.quantity,
              stockBefore: before,
              stockAfter: after,
              reason: "Sale",
              note: receiptNumber,
              referenceType: "sale",
              referenceId: data.saleId,
              createdBy: identity.uid,
              createdByName,
              createdAt: FieldValue.serverTimestamp(),
            });
          }
        }

        const grossProfitMinor = actualNetRevenueMinor - costOfGoodsSoldMinor;
        saleCogsMinor += costOfGoodsSoldMinor;
        saleActualNetRevenueMinor += actualNetRevenueMinor;
        saleGrossProfitMinor += grossProfitMinor;
        if (productId) {
          productProfitDelta.set(
            productId,
            (productProfitDelta.get(productId) ?? 0) + grossProfitMinor,
          );
        }

        itemMaps.push({
          saleItemId: item.saleItemId,
          productId,
          isCustomItem: item.isCustomItem,
          name: item.name,
          sku: item.sku || null,
          barcode: item.barcode || null,
          unit: item.unit,
          quantityInput: item.quantityInput || null,
          quantity: item.quantity,
          unitPriceInput: item.unitPriceInput || null,
          unitPriceMinor: item.unitPriceMinor,
          costPriceMinor: effectiveCostPriceMinor,
          discountType: item.discountType ?? null,
          discountValue: item.discountValue,
          discountAmountMinor: discount,
          lineSubtotalMinor: subtotal,
          lineTotalMinor: lineTotalAfterItem,
          trackStock: item.trackStock,
          batchAllocations,
          costOfGoodsSoldMinor,
          actualNetRevenueMinor,
          grossProfitMinor,
        });
      }

      transaction.set(
        counterRef,
        {
          nextNumber: nextNumber + 1,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      transaction.create(saleRef, {
        saleId: data.saleId,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        branchNameSnapshot: branchContext.branchName,
        branchCodeSnapshot: branchContext.branchCode,
        receiptNumber,
        customerId: data.customerId ?? null,
        customerName:
          data.customerName ??
          (customerSnapshot?.data()?.name as string | undefined) ??
          null,
        customerPhone:
          data.customerPhone ??
          (customerSnapshot?.data()?.phone as string | undefined) ??
          (customerSnapshot?.data()?.phoneNumber as string | undefined) ??
          null,
        items: itemMaps,
        itemCount: data.items.length,
        subtotalMinor: totals.subtotalMinor,
        discountMinor: totals.itemDiscountMinor + totals.orderDiscountMinor,
        taxMinor: totals.taxMinor,
        totalMinor: totals.totalMinor,
        amountPaidMinor: totals.amountPaidMinor,
        balanceDueMinor: totals.balanceDueMinor,
        changeMinor: totals.changeMinor,
        costOfGoodsSoldMinor: saleCogsMinor,
        actualNetRevenueMinor: saleActualNetRevenueMinor,
        grossProfitMinor: saleGrossProfitMinor,
        total: minorToMajor(totals.totalMinor),
        amountPaid: minorToMajor(totals.amountPaidMinor),
        currencyCode,
        currencySymbol,
        paymentMethod: data.paymentMethod,
        paymentStatus,
        saleStatus: "completed",
        status: "completed",
        note: data.note?.trim() ? data.note.trim() : null,
        receiptTemplateSnapshot: {
          businessName: (businessData.name as string | undefined) ?? null,
          businessPhone:
            (businessData.phoneNumber as string | undefined) ?? null,
          businessEmail: (businessData.email as string | undefined) ?? null,
          businessAddress: (businessData.address as string | undefined) ?? null,
          businessWebsite: (businessData.website as string | undefined) ?? null,
          businessTagline:
            (businessData.businessTagline as string | undefined) ?? null,
          logoUrl: (businessData.logoUrl as string | undefined) ?? null,
        },
        createdBy: identity.uid,
        createdByName,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      for (const productId of trackedProductIds) {
        const product = products.get(productId)!;
        const productData = product.data() ?? {};
        const tracksExpiry = productData.tracksExpiry === true;
        const working = mutableBatches.get(productId) ?? [];
        const quantity = tracksExpiry
          ? working
              .filter(
                (batch) =>
                  batch.quantityRemaining > 0 &&
                  batch.status !== "depleted" &&
                  batch.status !== "voided",
              )
              .reduce((sum, batch) => sum + batch.quantityRemaining, 0)
          : (runningStock.get(productId) ??
            numberValue(productData.quantity, 0));
        const summaryBatches = tracksExpiry
          ? working
          : [
              {
                id: `${productId}_aggregate`,
                quantityRemaining: quantity,
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
        const profitDelta = productProfitDelta.get(productId) ?? 0;
        const inventorySnapshot = inventories.get(productId)!;
        const inventoryData = inventorySnapshot.data() ?? {};
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
            quantity,
            reservedQuantity,
            availableQuantity: Math.max(0, quantity - reservedQuantity),
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
            potentialProfitRemainingMinor:
              summary.potentialProfitRemainingMinor,
            expiryStatus: summary.expiryStatus,
            nextExpiryDate: summary.nextExpiryDate
              ? dateOnlyTimestamp(summary.nextExpiryDate)
              : null,
            nextExpiryBatchId: summary.nextExpiryBatchId,
            nextExpiryBatchQuantity: summary.nextExpiryBatchQuantity,
            expiringQuantity: summary.expiringQuantity,
            expiredQuantity: summary.expiredQuantity,
            unknownExpiryQuantity: summary.unknownExpiryQuantity,
            realizedGrossProfitMinor: FieldValue.increment(profitDelta),
            updatedAt: FieldValue.serverTimestamp(),
            updatedBy: identity.uid,
            ...(inventorySnapshot.exists
              ? {}
              : {createdAt: FieldValue.serverTimestamp()}),
          },
          {merge: true},
        );
        const quantitySold = data.items
          .filter((item) => item.trackStock && item.productId === productId)
          .reduce((sum, item) => sum + item.quantity, 0);
        // Compatibility aggregate only.
        transaction.update(productRefs.get(productId)!, {
          quantity: FieldValue.increment(-quantitySold),
          realizedGrossProfitMinor: FieldValue.increment(profitDelta),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      if (customerRef && customerSnapshot?.exists) {
        const previousBalance = minorValue(
          customerSnapshot.data()?.balanceMinor,
          customerSnapshot.data()?.balance,
        );
        const updatedBalance = previousBalance + totals.balanceDueMinor;
        transaction.update(customerRef, {
          balanceMinor: updatedBalance,
          balance: minorToMajor(updatedBalance),
          totalCreditMinor: FieldValue.increment(totals.balanceDueMinor),
          totalSalesMinor: FieldValue.increment(totals.totalMinor),
          totalPaidMinor: FieldValue.increment(totals.amountPaidMinor),
          purchaseCount: FieldValue.increment(1),
          lastPurchaseAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        if (totals.balanceDueMinor > 0) {
          const ledgerRef = customerRef.collection("ledger").doc();
          transaction.create(ledgerRef, {
            type: "sale_credit",
            saleId: data.saleId,
            receiptNumber,
            branchId: branchContext.branchId,
            debitMinor: totals.balanceDueMinor,
            creditMinor: 0,
            balanceBeforeMinor: previousBalance,
            balanceAfterMinor: updatedBalance,
            createdBy: identity.uid,
            createdAt: FieldValue.serverTimestamp(),
          });
        }
      }

      transaction.create(activityRef, {
        activityId: activityRef.id,
        businessId: data.businessId,
        branchId: branchContext.branchId,
        type: "sale",
        title: "Sale completed",
        subtitle: `Receipt ${receiptNumber}`,
        amount: minorToMajor(totals.totalMinor),
        amountMinor: totals.totalMinor,
        currencyCode,
        referenceId: data.saleId,
        createdBy: identity.uid,
        createdByName,
        timestamp: FieldValue.serverTimestamp(),
      });

      const itemsSold = data.items.reduce(
        (sum, item) => sum + item.quantity,
        0,
      );
      transaction.set(
        businessRef
          .collection("analytics")
          .doc(`daily_${dateKey}_${branchContext.branchId}`),
        {
          dateKey,
          branchId: branchContext.branchId,
          grossSalesMinor: FieldValue.increment(totals.subtotalMinor),
          discountMinor: FieldValue.increment(
            totals.itemDiscountMinor + totals.orderDiscountMinor,
          ),
          taxMinor: FieldValue.increment(totals.taxMinor),
          netSalesMinor: FieldValue.increment(totals.totalMinor),
          amountPaidMinor: FieldValue.increment(totals.amountPaidMinor),
          creditCreatedMinor: FieldValue.increment(totals.balanceDueMinor),
          costOfGoodsSoldMinor: FieldValue.increment(saleCogsMinor),
          grossProfitMinor: FieldValue.increment(saleGrossProfitMinor),
          orderCount: FieldValue.increment(1),
          itemsSold: FieldValue.increment(itemsSold),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      return {
        saleId: data.saleId,
        receiptNumber,
        totalMinor: totals.totalMinor,
        amountPaidMinor: totals.amountPaidMinor,
        balanceDueMinor: totals.balanceDueMinor,
        changeMinor: totals.changeMinor,
        paymentMethod: data.paymentMethod,
        created: true,
      };
    });

    sendSuccess(res, result);
  },
);

function calculateSaleTotals(input: CompleteSaleInput): SaleTotals {
  const subtotalMinor = input.items.reduce(
    (sum, item) => sum + lineSubtotalMinor(item),
    0,
  );
  const itemDiscountMinor = input.items.reduce(
    (sum, item) => sum + lineDiscountMinor(item),
    0,
  );
  const afterItems = Math.max(0, subtotalMinor - itemDiscountMinor);
  const orderDiscountMinor = calculateDiscount(
    afterItems,
    input.orderDiscountType,
    input.orderDiscountValue ?? 0,
  );
  const taxable = Math.max(0, afterItems - orderDiscountMinor);
  const taxMinor =
    input.taxEnabled && input.taxPercentage > 0
      ? Math.round(taxable * (input.taxPercentage / 100))
      : 0;
  const totalMinor = Math.max(0, taxable + taxMinor);
  const amountPaidMinor = Math.max(0, input.amountPaidMinor);
  return {
    subtotalMinor,
    itemDiscountMinor,
    orderDiscountMinor,
    taxMinor,
    totalMinor,
    amountPaidMinor: Math.min(amountPaidMinor, totalMinor),
    balanceDueMinor: Math.max(0, totalMinor - amountPaidMinor),
    changeMinor: Math.max(0, amountPaidMinor - totalMinor),
  };
}

function lineSubtotalMinor(item: SaleItemInput): number {
  return Math.round(item.quantity * item.unitPriceMinor);
}

function lineDiscountMinor(item: SaleItemInput): number {
  return calculateDiscount(
    lineSubtotalMinor(item),
    item.discountType,
    item.discountValue ?? 0,
  );
}

function calculateDiscount(
  subtotal: number,
  type: "fixed" | "percentage" | null | undefined,
  value: number,
): number {
  if (!type || value <= 0) return 0;
  if (!Number.isFinite(value)) {
    throw new Error("Discount must be a valid number.");
  }
  if (type === "percentage" && (value < 0 || value > 100)) {
    throw new Error("Percentage discount must be between 0 and 100.");
  }
  const discount =
    type === "fixed"
      ? Math.round(value * 100)
      : Math.round(subtotal * (value / 100));
  return Math.min(subtotal, Math.max(0, discount));
}

function applyAllocationsToWorkingBatches(
  batches: FefoBatchInput[],
  allocations: FefoAllocation[],
): void {
  for (const allocation of allocations) {
    const batch = batches.find((row) => row.id === allocation.batchId);
    if (!batch) continue;
    batch.quantityRemaining = Math.max(
      0,
      batch.quantityRemaining - allocation.quantity,
    );
    if (batch.quantityRemaining <= 1e-9) {
      batch.quantityRemaining = 0;
      batch.status = "depleted";
    }
  }
}

function batchSummaryInput(
  id: string,
  data: Record<string, unknown>,
): InventoryBatchSummaryInput & FefoBatchInput {
  const timestamp = data.expiryDate;
  const expiryDate =
    timestamp instanceof Timestamp
      ? timestamp.toDate().toISOString().slice(0, 10)
      : typeof timestamp === "string"
        ? timestamp.slice(0, 10)
        : null;
  const rawStatus = String(data.status ?? "active");
  const status: FefoBatchInput["status"] =
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
