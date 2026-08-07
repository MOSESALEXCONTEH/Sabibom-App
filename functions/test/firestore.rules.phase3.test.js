const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc } = require('firebase/firestore');

const projectId = 'sabibom-phase3-rules';
const rules = readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8');
let testEnv;

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'businesses/bizA'), {
      businessId: 'bizA', ownerId: 'ownerA', name: 'Biz A',
    });
    await setDoc(doc(db, 'businesses/bizB'), {
      businessId: 'bizB', ownerId: 'ownerB', name: 'Biz B',
    });
    await setDoc(doc(db, 'businesses/bizA/members/ownerA'), {
      userId: 'ownerA', role: 'owner', isOwner: true, status: 'active',
      assignedBranchIds: ['main', 'east'], allBranchesAccess: true,
    });
    await setDoc(doc(db, 'businesses/bizA/members/cashierA'), {
      userId: 'cashierA', role: 'cashier', status: 'active',
      assignedBranchIds: ['main'], allBranchesAccess: false,
      permissions: ['view_branch'],
    });
    await setDoc(doc(db, 'businesses/bizA/members/reporterA'), {
      userId: 'reporterA', role: 'staff', status: 'active',
      assignedBranchIds: ['main'], allBranchesAccess: false,
      permissions: ['view_branch', 'view_combined_reports'],
    });
    await setDoc(doc(db, 'businesses/bizB/members/ownerB'), {
      userId: 'ownerB', role: 'owner', isOwner: true, status: 'active',
      assignedBranchIds: ['main'], allBranchesAccess: true,
    });
    await setDoc(doc(db, 'businesses/bizA/branches/main'), {
      branchId: 'main', businessId: 'bizA', name: 'Main', code: 'MAIN',
      isMainBranch: true, status: 'active',
    });
    await setDoc(doc(db, 'businesses/bizA/branches/east'), {
      branchId: 'east', businessId: 'bizA', name: 'East', code: 'EAST',
      isMainBranch: false, status: 'active',
    });
    await setDoc(doc(db, 'businesses/bizA/branches/inactive'), {
      branchId: 'inactive', businessId: 'bizA', name: 'Closed', code: 'CLOSED',
      isMainBranch: false, status: 'inactive',
    });
    await setDoc(doc(db, 'businesses/bizB/branches/main'), {
      branchId: 'main', businessId: 'bizB', name: 'Main', code: 'MAIN',
      isMainBranch: true, status: 'active',
    });
    await setDoc(doc(db, 'businesses/bizA/products/p1'), {
      productId: 'p1', businessId: 'bizA', name: 'Product', quantity: 40,
    });
    await setDoc(doc(db, 'businesses/bizA/branches/main/inventory/p1'), {
      businessId: 'bizA', branchId: 'main', productId: 'p1', quantity: 40,
    });
    await setDoc(doc(db, 'businesses/bizA/branches/east/inventory/p1'), {
      businessId: 'bizA', branchId: 'east', productId: 'p1', quantity: 15,
    });
    await setDoc(doc(db, 'businesses/bizA/branches/inactive/inventory/p1'), {
      businessId: 'bizA', branchId: 'inactive', productId: 'p1', quantity: 5,
    });
    await setDoc(doc(db, 'businesses/bizB/products/p1'), {
      productId: 'p1', businessId: 'bizB', name: 'Other product', quantity: 9,
    });
    await setDoc(doc(db, 'businesses/bizB/branches/main/inventory/p1'), {
      businessId: 'bizB', branchId: 'main', productId: 'p1', quantity: 9,
    });
  });
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({projectId, firestore: {rules}});
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed();
});

test.after(async () => {
  if (testEnv) await testEnv.cleanup();
});

test('product definitions are readable business-wide', async () => {
  const db = testEnv.authenticatedContext('cashierA').firestore();
  const snapshot = await assertSucceeds(getDoc(doc(db, 'businesses/bizA/products/p1')));
  assert.equal(snapshot.exists(), true);
});

test('assigned staff can read own branch inventory', async () => {
  const db = testEnv.authenticatedContext('cashierA').firestore();
  await assertSucceeds(getDoc(doc(db, 'businesses/bizA/branches/main/inventory/p1')));
});

test('assigned staff cannot read an unassigned branch inventory', async () => {
  const db = testEnv.authenticatedContext('cashierA').firestore();
  await assertFails(getDoc(doc(db, 'businesses/bizA/branches/east/inventory/p1')));
});

test('combined reports permission does not grant raw unassigned inventory access', async () => {
  const db = testEnv.authenticatedContext('reporterA').firestore();
  await assertFails(getDoc(doc(db, 'businesses/bizA/branches/east/inventory/p1')));
});

test('cashier can update assigned active branch stock', async () => {
  const db = testEnv.authenticatedContext('cashierA').firestore();
  await assertSucceeds(updateDoc(doc(db, 'businesses/bizA/branches/main/inventory/p1'), {
    quantity: 39,
    availableQuantity: 39,
  }));
});

test('cashier cannot mutate inactive branch stock', async () => {
  const db = testEnv.authenticatedContext('cashierA').firestore();
  await assertFails(updateDoc(doc(db, 'businesses/bizA/branches/inactive/inventory/p1'), {
    quantity: 4,
  }));
});

test('cross-business inventory access is denied', async () => {
  const db = testEnv.authenticatedContext('cashierA').firestore();
  await assertFails(getDoc(doc(db, 'businesses/bizB/branches/main/inventory/p1')));
});

test('negative branch inventory quantity is denied', async () => {
  const db = testEnv.authenticatedContext('cashierA').firestore();
  await assertFails(updateDoc(doc(db, 'businesses/bizA/branches/main/inventory/p1'), {
    quantity: -1,
  }));
});

test('new branch inventory must match path ownership', async () => {
  const db = testEnv.authenticatedContext('ownerA').firestore();
  await assertFails(setDoc(doc(db, 'businesses/bizA/branches/main/inventory/bad'), {
    businessId: 'bizB', branchId: 'main', productId: 'bad', quantity: 1,
  }));
});

test('recursive fallback cannot create an unlisted inventory-like record', async () => {
  const db = testEnv.authenticatedContext('cashierA').firestore();
  await assertFails(setDoc(doc(db, 'businesses/bizA/inventory_shadow/p1'), {
    businessId: 'bizA', branchId: 'main', productId: 'p1', quantity: 100,
  }));
});
