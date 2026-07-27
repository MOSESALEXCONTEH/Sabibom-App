import type {VercelRequest, VercelResponse} from "@vercel/node";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {adminFirestore} from "../../../config/firebase-admin";
import {authenticateRequest} from "../../../middleware/authenticate-request";
import {businessIdSchema} from "../../../schemas/common-schemas";
import type {FefoBatchInput} from "../../../services/inventory/fefo-allocation";
import {expiryStatusForDate} from "../../../services/inventory/product-intelligence";
import {
  summarizeInventoryBatches,
  type InventoryBatchSummaryInput,
} from "../../../services/inventory/purchase-intelligence";
import {requireAppPermission} from "../../../services/team/membership-service";
import {errors} from "../../../utils/api-errors";
import {sendSuccess} from "../../../utils/api-response";
import {createHandler, readJsonBody} from "../../../utils/handler";
import {minorToMajor} from "../../../utils/money";

const voidSaleSchema = z.object({
  businessId: businessIdSchema,
  saleId: z.string().trim().min(1).max(128),
  reason: z.string().trim().min(2).max(500),
  voidedByName: z.string().trim().max(160).nullish(),
});

export default createHandler(
  ["POST"],
  async (req: VercelRequest, res: VercelResponse) => {
    const identity = await authenticateRequest(req);
    const parsed = voidSaleSchema.safeParse(readJsonBody(req));
    if (!parsed.success) {
      throw errors.invalidArgument("Enter a void reason and try again.");
    }
    const data = parsed.data;
    await requireAppPermission({
      uid: identity.uid,
      businessId: data.businessId,
      permission: "void_sale",
    });

    const db = adminFirestore();
    const businessRef = db.collection("businesses").doc(data.businessId);
    const saleRef = businessRef.collection("sales").doc(data.saleId);
    const activityRef = businessRef.collection("activity").doc();
    const voidedByName =
      data.voidedByName?.trim() || identity.email || "Team member";
    const now = new Date();

    const result = await db.runTransaction(async (transaction) => {
      const [businessSnapshot, saleSnapshot] = await Promise.all([
        transaction.get(businessRef),
        transaction.get(saleRef),
      ]);
      if (!businessSnapshot.exists) {
        throw errors.notFound("The selected business no longer exists.");
      }
      if (!saleSnapshot.exists) {
        throw errors.notFound("Sale not found.");
      }

      const saleData = saleSnapshot.data() ?? {};
      const status = String(saleData.saleStatus ?? saleData.status ?? "");
      const receiptNumber =
        (saleData.receiptNumber as string | undefined) ?? data.saleId;
      if (status === "voided") {
        return {
          saleId: data.saleId,
          receiptNumber,
          voided: true,
          alreadyVoided: true,
        };
      }

      const rawItems = (saleData.items as unknown[] | undefined) ?? [];
      const items = rawItems
        .filter((row): row is Record<string, unknown> =>
          Boolean(row) && typeof row === "object",
        )
        .map((row) => row);

      const productIds = [
        ...new Set(
          items
            .map((item) => {
              const productId =
                typeof item.productId === "string" ? item.productId.trim() : "";
              const trackStock = item.trackStock === true;
              return trackStock && productId ? productId : null;
            })
            .filter((id): id is string => Boolean(id)),
        ),
      ];

      const productRefs = new Map(
        productIds.map((productId) => [
          productId,
          businessRef.collection("products").doc(productId),
        ]),
      );
      const batchQueries = new Map(
        productIds.map((productId) => [
          productId,
          businessRef
            .collection("inventory_batches")
            .where("productId", "==", productId),
        ]),
      );

      const customerId =
        typeof saleData.customerId === "string"
          ? saleData.customerId.trim()
          : "";
      const customerRef = customerId
        ? businessRef.collection("customers").doc(customerId)
        : null;

      const [customerSnapshot, productResults, batchResults] =
        await Promise.all([
          customerRef ? transaction.get(customerRef) : Promise.resolve(null),
          Promise.all(
            productIds.map((productId) =>
              transaction.get(productRefs.get(productId)!),
            ),
          ),
          Promise.all(
            productIds.map((productId) =>
              transaction.get(batchQueries.get(productId)!),
            ),
          ),
        ]);

      const products = new Map(
        productIds.map((productId, index) => [
          productId,
          productResults[index],
        ]),
      );
      const batchesByProduct = new Map(
        productIds.map((productId, index) => [
          productId,
          batchResults[index].docs.map((snapshot) => ({
            ref: snapshot.ref,
            summary: batchSummaryInput(snapshot.id, snapshot.data()),
          })),
        ]),
      );
      const workingBatches = new Map<string, FefoBatchInput[]>();
      for (const productId of productIds) {
        workingBatches.set(
          productId,
          (batchesByProduct.get(productId) ?? []).map((row) => ({
            ...row.summary,
          })),
        );
      }

      const totalMinor = minorValue(saleData.totalMinor, saleData.total);
      const subtotalMinor = minorValue(
        saleData.subtotalMinor,
        saleData.subtotal,
      );
      const discountMinor = minorValue(
        saleData.discountMinor,
        saleData.discount,
      );
      const taxMinor = minorValue(saleData.taxMinor, saleData.tax);
      const amountPaidMinor = minorValue(
        saleData.amountPaidMinor,
        saleData.amountPaid,
      );
      const balanceDueMinor = numberValue(saleData.balanceDueMinor, 0);
      const saleCogsMinor = numberValue(saleData.costOfGoodsSoldMinor, 0);
      const saleGrossProfitMinor = numberValue(saleData.grossProfitMinor, 0);
      const createdAt =
        saleData.createdAt instanceof Timestamp
          ? saleData.createdAt.toDate()
          : now;
      const timezone =
        (businessSnapshot.data()?.timezone as string | undefined) ??
        "Africa/Freetown";
      const dateKey =
        typeof saleData.dateKey === "string" && saleData.dateKey.trim()
          ? saleData.dateKey.trim()
          : businessDateKey(createdAt, timezone);
      const currencyCode =
        (saleData.currencyCode as string | undefined) ??
        (businessSnapshot.data()?.currencyCode as string | undefined) ??
        "SLE";
      const itemsSold = items.reduce(
        (sum, item) => sum + numberValue(item.quantity, 0),
        0,
      );

      const runningStock = new Map<string, number>();
      const productProfitDelta = new Map<string, number>();
      const touchedBatchIds = new Map<string, Set<string>>();

      for (const item of items) {
        const productId =
          typeof item.productId === "string" ? item.productId.trim() : "";
        const trackStock = item.trackStock === true;
        const qty = numberValue(item.quantity, 0);
        if (!trackStock || !productId || qty <= 0) continue;
        const product = products.get(productId);
        if (!product?.exists) continue;
        const productData = product.data() ?? {};
        const before =
          runningStock.get(productId) ?? numberValue(productData.quantity, 0);
        const reminderThresholdDays = numberValue(
          productData.defaultExpiryReminderDays,
          30,
        );

        const allocations = readBatchAllocations(item.batchAllocations);
        if (allocations.length > 0) {
          const working = workingBatches.get(productId) ?? [];
          const touched = touchedBatchIds.get(productId) ?? new Set<string>();
          let allocationStockBefore = before;
          for (const allocation of allocations) {
            const batch = working.find((row) => row.id === allocation.batchId);
            const batchRow = (batchesByProduct.get(productId) ?? []).find(
              (row) => row.summary.id === allocation.batchId,
            );
            if (!batch || !batchRow) continue;
            batch.quantityRemaining += allocation.quantity;
            batch.status = restoredBatchStatus(batch, {
              timezone,
              reminderThresholdDays,
              now,
            });
            touched.add(allocation.batchId);
            const allocationAfter =
              allocationStockBefore + allocation.quantity;
            const movementRef = businessRef
              .collection("inventory_movements")
              .doc();
            transaction.create(movementRef, {
              id: movementRef.id,
              productId,
              productName: (item.name as string | undefined) ?? "Item",
              batchId: allocation.batchId,
              type: "stock_in",
              quantityChange: allocation.quantity,
              stockBefore: allocationStockBefore,
              stockAfter: allocationAfter,
              reason: "Sale void",
              note: data.reason,
              referenceType: "sale_void",
              referenceId: data.saleId,
              createdBy: identity.uid,
              createdByName: voidedByName,
              createdAt: FieldValue.serverTimestamp(),
            });
            allocationStockBefore = allocationAfter;
          }
          touchedBatchIds.set(productId, touched);
          workingBatches.set(productId, working);
          runningStock.set(productId, before + qty);
        } else {
          const after = before + qty;
          runningStock.set(productId, after);
          const movementRef = businessRef
            .collection("inventory_movements")
            .doc();
          transaction.create(movementRef, {
            id: movementRef.id,
            productId,
            productName: (item.name as string | undefined) ?? "Item",
            type: "stock_in",
            quantityChange: qty,
            stockBefore: before,
            stockAfter: after,
            reason: "Sale void",
            note: data.reason,
            referenceType: "sale_void",
            referenceId: data.saleId,
            createdBy: identity.uid,
            createdByName: voidedByName,
            createdAt: FieldValue.serverTimestamp(),
          });
        }

        const lineGross = numberValue(
          item.grossProfitMinor,
          numberValue(item.actualNetRevenueMinor, 0) -
            numberValue(
              item.costOfGoodsSoldMinor,
              Math.round(qty * numberValue(item.costPriceMinor, 0)),
            ),
        );
        productProfitDelta.set(
          productId,
          (productProfitDelta.get(productId) ?? 0) + lineGross,
        );
      }

      for (const [productId, touched] of touchedBatchIds) {
        const working = workingBatches.get(productId) ?? [];
        for (const batchId of touched) {
          const batch = working.find((row) => row.id === batchId);
          const batchRow = (batchesByProduct.get(productId) ?? []).find(
            (row) => row.summary.id === batchId,
          );
          if (!batch || !batchRow) continue;
          transaction.update(batchRow.ref, {
            quantityRemaining: batch.quantityRemaining,
            status: batch.status,
            depletedAt: null,
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      }

      transaction.update(saleRef, {
        saleStatus: "voided",
        status: "voided",
        voidReason: data.reason,
        voidedBy: identity.uid,
        voidedByName,
        voidedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: identity.uid,
      });

      for (const productId of productIds) {
        const product = products.get(productId);
        if (!product?.exists) continue;
        const productData = product.data() ?? {};
        const tracksExpiry = productData.tracksExpiry === true;
        const working = workingBatches.get(productId) ?? [];
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
        transaction.update(productRefs.get(productId)!, {
          quantity,
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
          realizedGrossProfitMinor: FieldValue.increment(-profitDelta),
          updatedAt: FieldValue.serverTimestamp(),
          updatedBy: identity.uid,
        });
      }

      if (customerRef && customerSnapshot?.exists && balanceDueMinor > 0) {
        const previousBalance = minorValue(
          customerSnapshot.data()?.balanceMinor,
          customerSnapshot.data()?.balance,
        );
        const updatedBalance = previousBalance - balanceDueMinor;
        transaction.update(customerRef, {
          balanceMinor: updatedBalance,
          balance: minorToMajor(updatedBalance),
          totalCreditMinor: FieldValue.increment(-balanceDueMinor),
          totalSalesMinor: FieldValue.increment(-totalMinor),
          totalPaidMinor: FieldValue.increment(-amountPaidMinor),
          purchaseCount: FieldValue.increment(-1),
          updatedAt: FieldValue.serverTimestamp(),
          updatedBy: identity.uid,
        });
        const ledgerRef = customerRef.collection("ledger").doc();
        transaction.create(ledgerRef, {
          type: "sale_void",
          saleId: data.saleId,
          receiptNumber,
          debitMinor: 0,
          creditMinor: balanceDueMinor,
          balanceBeforeMinor: previousBalance,
          balanceAfterMinor: updatedBalance,
          createdBy: identity.uid,
          createdByName: voidedByName,
          createdAt: FieldValue.serverTimestamp(),
        });
      } else if (customerRef && customerSnapshot?.exists) {
        transaction.update(customerRef, {
          totalSalesMinor: FieldValue.increment(-totalMinor),
          totalPaidMinor: FieldValue.increment(-amountPaidMinor),
          purchaseCount: FieldValue.increment(-1),
          updatedAt: FieldValue.serverTimestamp(),
          updatedBy: identity.uid,
        });
      }

      transaction.create(activityRef, {
        activityId: activityRef.id,
        businessId: data.businessId,
        type: "sale_void",
        title: "Sale voided",
        subtitle: `Receipt ${receiptNumber} · ${data.reason}`,
        amount: minorToMajor(totalMinor),
        amountMinor: totalMinor,
        currencyCode,
        referenceId: data.saleId,
        createdBy: identity.uid,
        createdByName: voidedByName,
        timestamp: FieldValue.serverTimestamp(),
      });

      transaction.set(
        businessRef.collection("analytics").doc(`daily_${dateKey}`),
        {
          dateKey,
          grossSalesMinor: FieldValue.increment(-subtotalMinor),
          discountMinor: FieldValue.increment(-discountMinor),
          taxMinor: FieldValue.increment(-taxMinor),
          netSalesMinor: FieldValue.increment(-totalMinor),
          amountPaidMinor: FieldValue.increment(-amountPaidMinor),
          creditCreatedMinor: FieldValue.increment(-balanceDueMinor),
          costOfGoodsSoldMinor: FieldValue.increment(-saleCogsMinor),
          grossProfitMinor: FieldValue.increment(-saleGrossProfitMinor),
          orderCount: FieldValue.increment(-1),
          itemsSold: FieldValue.increment(-itemsSold),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      return {
        saleId: data.saleId,
        receiptNumber,
        voided: true,
        alreadyVoided: false,
      };
    });

    sendSuccess(res, result);
  },
);

function restoredBatchStatus(
  batch: FefoBatchInput,
  options: {
    timezone: string;
    reminderThresholdDays: number;
    now: Date;
  },
): FefoBatchInput["status"] {
  if (
    batch.expiryDateKnown &&
    batch.expiryDate &&
    expiryStatusForDate({
      expiryDate: batch.expiryDate,
      reminderThresholdDays: options.reminderThresholdDays,
      timezone: options.timezone,
      now: options.now,
    }) === "expired"
  ) {
    return "expired";
  }
  return "active";
}

function readBatchAllocations(
  raw: unknown,
): Array<{batchId: string; quantity: number; unitCostMinor: number}> {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((row): row is Record<string, unknown> =>
      Boolean(row) && typeof row === "object",
    )
    .map((row) => ({
      batchId: typeof row.batchId === "string" ? row.batchId : "",
      quantity: numberValue(row.quantity, 0),
      unitCostMinor: Math.round(numberValue(row.unitCostMinor, 0)),
    }))
    .filter((row) => row.batchId && row.quantity > 0);
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
