/**
 * Idempotent legacy stock → inventory_batches migration.
 *
 * Usage:
 *   DRY_RUN=1 npx ts-node scripts/migrate-legacy-inventory-batches.ts
 *   npx ts-node scripts/migrate-legacy-inventory-batches.ts
 *
 * Creates one legacy_migration batch per tracked product with quantity > 0
 * that does not already have any inventory_batches docs. Does not rewrite
 * historical sales or inventory_movements.
 */
import {FieldValue} from "firebase-admin/firestore";
import {adminFirestore} from "../src/config/firebase-admin";
import {
  calculatePotentialProfit,
} from "../src/services/inventory/product-intelligence";

const dryRun = process.env.DRY_RUN === "1" || process.env.DRY_RUN === "true";
const businessLimit = Number(process.env.BUSINESS_LIMIT ?? "50");

async function main() {
  const db = adminFirestore();
  const businesses = await db.collection("businesses").limit(businessLimit).get();
  let migrated = 0;
  let skipped = 0;

  for (const business of businesses.docs) {
    const products = await business.ref.collection("products").get();
    for (const product of products.docs) {
      const data = product.data();
      const quantity = Number(data.quantity ?? 0);
      const trackStock = data.trackStock !== false;
      if (!trackStock || !Number.isFinite(quantity) || quantity <= 0) {
        skipped += 1;
        continue;
      }
      const existing = await business.ref
        .collection("inventory_batches")
        .where("productId", "==", product.id)
        .limit(1)
        .get();
      if (!existing.empty) {
        skipped += 1;
        continue;
      }

      const unitCostMinor =
        typeof data.costPriceMinor === "number"
          ? Math.round(data.costPriceMinor)
          : Math.round(Number(data.costPrice ?? 0) * 100);
      const sellingPriceMinor =
        typeof data.sellingPriceMinor === "number"
          ? Math.round(data.sellingPriceMinor)
          : Math.round(Number(data.sellingPrice ?? data.price ?? 0) * 100);
      const profit = calculatePotentialProfit({
        quantity,
        unitCostMinor,
        sellingPriceMinor,
      });
      const batchRef = business.ref
        .collection("inventory_batches")
        .doc(`${product.id}_legacy`);
      const checkpoint = business.ref
        .collection("migration_checkpoints")
        .doc(`legacy_batches_${product.id}`);

      console.log(
        `${dryRun ? "[dry-run] " : ""}migrate ${business.id}/${product.id} qty=${quantity}`,
      );
      if (dryRun) {
        migrated += 1;
        continue;
      }

      await db.runTransaction(async (tx) => {
        const checkpointSnap = await tx.get(checkpoint);
        if (checkpointSnap.exists) return;
        const batchSnap = await tx.get(batchRef);
        if (batchSnap.exists) {
          tx.set(checkpoint, {
            productId: product.id,
            state: "already_present",
            updatedAt: FieldValue.serverTimestamp(),
          });
          return;
        }
        tx.create(batchRef, {
          businessId: business.id,
          productId: product.id,
          productName: data.name ?? "Unnamed product",
          sku: data.sku ?? null,
          sourceType: "legacy_migration",
          sourceId: product.id,
          sourceNumber: null,
          quantityReceived: quantity,
          quantityRemaining: quantity,
          unitCostMinor,
          sellingPriceAtReceiptMinor: sellingPriceMinor,
          expiryDate: null,
          expiryDateKnown: false,
          receivedAt: FieldValue.serverTimestamp(),
          status: "active",
          createdBy: "system_migration",
          createdByName: "Legacy migration",
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          depletedAt: null,
        });
        tx.set(
          product.ref,
          {
            tracksExpiry: data.tracksExpiry === true,
            expiryStatus:
              data.tracksExpiry === true
                ? data.expiryStatus ?? "safe"
                : "not_tracked",
            unknownExpiryQuantity:
              data.tracksExpiry === true ? quantity : 0,
            ...profit,
            realizedGrossProfitMinor:
              typeof data.realizedGrossProfitMinor === "number"
                ? data.realizedGrossProfitMinor
                : 0,
            profitIsEstimated: true,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
        tx.set(checkpoint, {
          productId: product.id,
          batchId: batchRef.id,
          state: "migrated",
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
      migrated += 1;
    }
  }

  console.log(
    `Done. migrated=${migrated} skipped=${skipped} dryRun=${dryRun}`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
