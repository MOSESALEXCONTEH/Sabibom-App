#!/usr/bin/env node
/* eslint-disable no-console */

/**
 * One-time, opt-in migration for SabiBom branch inventory.
 *
 * Dry-run is the default:
 *   node scripts/migrate-branch-inventory.cjs
 *
 * Apply only after a backup and review:
 *   node scripts/migrate-branch-inventory.cjs --apply
 *
 * This script never runs during app startup or deployment.
 */
const {applicationDefault, cert, getApps, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

const APPLY = process.argv.includes("--apply");
const BATCH_LIMIT = 250;
const TOP_LEVEL_BRANCH_OWNED = [
  "sales",
  "expenses",
  "purchases",
  "purchase_returns",
  "inventory_batches",
  "inventory_movements",
  "activity",
  "analytics",
  "supplier_payments",
];

function firebaseCredential() {
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL?.trim();
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, "\n");
  if (projectId && clientEmail && privateKey) {
    return cert({projectId, clientEmail, privateKey});
  }
  return applicationDefault();
}

if (getApps().length === 0) {
  initializeApp({credential: firebaseCredential()});
}
const db = getFirestore();

const counts = {
  businessesScanned: 0,
  mainBranchesPlanned: 0,
  mainBranchesCreated: 0,
  inventoryPlanned: 0,
  inventoryCreated: 0,
  branchlessRecordsPlanned: 0,
  branchlessRecordsUpdated: 0,
  skippedAlreadyMigrated: 0,
  failures: 0,
};

class BufferedWriter {
  constructor() {
    this.batch = db.batch();
    this.size = 0;
  }

  async set(reference, data, options = {merge: true}) {
    if (!APPLY) return;
    this.batch.set(reference, data, options);
    this.size += 1;
    if (this.size >= BATCH_LIMIT) await this.flush();
  }

  async flush() {
    if (!APPLY || this.size === 0) return;
    await this.batch.commit();
    this.batch = db.batch();
    this.size = 0;
  }
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function number(value, fallback = 0) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function hasBranchId(data) {
  return text(data?.branchId).length > 0;
}

function inventoryFromLegacyProduct(businessId, productId, product) {
  const quantity = Math.max(0, number(product.quantity));
  const reservedQuantity = Math.max(0, number(product.reservedQuantity));
  const averageUnitCostMinor = Math.round(
    number(product.costPriceMinor, number(product.costPrice) * 100),
  );
  const sellingPriceMinor = Math.round(
    number(
      product.sellingPriceMinor,
      number(product.sellingPrice, number(product.price)) * 100,
    ),
  );
  return {
    businessId,
    branchId: "main",
    productId,
    quantity,
    reservedQuantity,
    availableQuantity: Math.max(0, quantity - reservedQuantity),
    lowStockThreshold: Math.max(0, number(product.lowStockThreshold)),
    averageUnitCostMinor,
    stockCostValueMinor: Math.round(quantity * averageUnitCostMinor),
    expectedStockRevenueMinor: Math.round(quantity * sellingPriceMinor),
    potentialProfitRemainingMinor: Math.round(
      quantity * (sellingPriceMinor - averageUnitCostMinor),
    ),
    realizedGrossProfitMinor: Math.round(number(product.realizedGrossProfitMinor)),
    expiringQuantity: Math.max(0, number(product.expiringQuantity)),
    expiredQuantity: Math.max(0, number(product.expiredQuantity)),
    unknownExpiryQuantity: Math.max(0, number(product.unknownExpiryQuantity)),
    nextExpiryDate: product.nextExpiryDate ?? null,
    nextExpiryBatchId: product.nextExpiryBatchId ?? null,
    nextExpiryBatchQuantity: Math.max(0, number(product.nextExpiryBatchQuantity)),
    expiryStatus: text(product.expiryStatus) || "not_tracked",
    migratedFromLegacyProduct: true,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function ensureMainBranch(businessRef, businessData, writer) {
  const mainRef = businessRef.collection("branches").doc("main");
  const mainSnapshot = await mainRef.get();
  if (mainSnapshot.exists) return mainRef;

  counts.mainBranchesPlanned += 1;
  await writer.set(mainRef, {
    branchId: "main",
    businessId: businessRef.id,
    name: "Main Branch",
    code: "MAIN",
    address: text(businessData.address) || null,
    city: text(businessData.city) || null,
    country: text(businessData.country) || null,
    phone: text(businessData.phone) || null,
    email: text(businessData.email) || null,
    managerUid: null,
    isMainBranch: true,
    status: "active",
    createdBy: text(businessData.ownerId) || null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    createdByMigration: true,
  });
  if (APPLY) counts.mainBranchesCreated += 1;
  return mainRef;
}

async function migrateProductInventory(businessRef, mainRef, writer) {
  const products = await businessRef.collection("products").get();
  for (const productSnapshot of products.docs) {
    const inventoryRef = mainRef.collection("inventory").doc(productSnapshot.id);
    const inventorySnapshot = await inventoryRef.get();
    if (inventorySnapshot.exists) {
      counts.skippedAlreadyMigrated += 1;
      continue;
    }
    counts.inventoryPlanned += 1;
    await writer.set(
      inventoryRef,
      inventoryFromLegacyProduct(
        businessRef.id,
        productSnapshot.id,
        productSnapshot.data(),
      ),
    );
    if (APPLY) counts.inventoryCreated += 1;
  }
}

async function migrateCollectionBranchIds(businessRef, collectionName, writer) {
  const snapshot = await businessRef.collection(collectionName).get();
  for (const document of snapshot.docs) {
    if (hasBranchId(document.data())) {
      counts.skippedAlreadyMigrated += 1;
      continue;
    }
    counts.branchlessRecordsPlanned += 1;
    await writer.set(document.ref, {
      businessId: businessRef.id,
      branchId: "main",
      branchMigratedAt: FieldValue.serverTimestamp(),
    });
    if (APPLY) counts.branchlessRecordsUpdated += 1;
  }
}

async function migrateNestedLedgers(businessRef, parentCollection, writer) {
  const parents = await businessRef.collection(parentCollection).get();
  for (const parent of parents.docs) {
    const ledger = await parent.ref.collection("ledger").get();
    for (const document of ledger.docs) {
      if (hasBranchId(document.data())) {
        counts.skippedAlreadyMigrated += 1;
        continue;
      }
      counts.branchlessRecordsPlanned += 1;
      await writer.set(document.ref, {
        businessId: businessRef.id,
        branchId: "main",
        branchMigratedAt: FieldValue.serverTimestamp(),
      });
      if (APPLY) counts.branchlessRecordsUpdated += 1;
    }
  }
}

async function run() {
  console.log(APPLY ? "APPLY mode enabled." : "DRY RUN only; no writes will occur.");
  const businesses = await db.collection("businesses").get();
  const writer = new BufferedWriter();

  for (const businessSnapshot of businesses.docs) {
    counts.businessesScanned += 1;
    try {
      const businessRef = businessSnapshot.ref;
      const mainRef = await ensureMainBranch(
        businessRef,
        businessSnapshot.data(),
        writer,
      );
      await migrateProductInventory(businessRef, mainRef, writer);
      for (const collectionName of TOP_LEVEL_BRANCH_OWNED) {
        await migrateCollectionBranchIds(businessRef, collectionName, writer);
      }
      await migrateNestedLedgers(businessRef, "customers", writer);
      await migrateNestedLedgers(businessRef, "suppliers", writer);
    } catch (error) {
      counts.failures += 1;
      console.error(`Migration failed for business ${businessSnapshot.id}:`, error?.code ?? "unknown_error");
    }
  }
  await writer.flush();
  console.log(JSON.stringify({mode: APPLY ? "apply" : "dry-run", ...counts}, null, 2));
  if (counts.failures > 0) process.exitCode = 1;
}

run().catch((error) => {
  console.error("Migration stopped:", error?.code ?? "unknown_error");
  process.exitCode = 1;
});
