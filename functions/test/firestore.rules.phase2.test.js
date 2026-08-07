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

const projectId = 'sabibom-phase2-rules';
const rules = readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8');

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

async function seedBusinessData() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await setDoc(doc(db, 'businesses/bizA'), {
      businessId: 'bizA',
      ownerId: 'ownerA',
      name: 'Biz A',
    });
    await setDoc(doc(db, 'businesses/bizB'), {
      businessId: 'bizB',
      ownerId: 'ownerB',
      name: 'Biz B',
    });

    await setDoc(doc(db, 'businesses/bizA/members/ownerA'), {
      userId: 'ownerA',
      role: 'owner',
      roleId: 'owner',
      isOwner: true,
      status: 'active',
      assignedBranchIds: ['main'],
      allBranchesAccess: true,
    });

    await setDoc(doc(db, 'businesses/bizA/members/cashierA'), {
      userId: 'cashierA',
      role: 'cashier',
      roleId: 'cashier',
      status: 'active',
      assignedBranchIds: ['main'],
      allBranchesAccess: false,
      permissions: ['create_expense', 'view_branch'],
    });

    await setDoc(doc(db, 'businesses/bizA/members/eastStaff'), {
      userId: 'eastStaff',
      role: 'staff',
      roleId: 'staff',
      status: 'active',
      assignedBranchIds: ['east'],
      allBranchesAccess: false,
      permissions: ['create_expense', 'view_branch'],
    });

    await setDoc(doc(db, 'businesses/bizA/members/mainStaff'), {
      userId: 'mainStaff',
      role: 'staff',
      roleId: 'staff',
      status: 'active',
      assignedBranchIds: ['main'],
      allBranchesAccess: false,
      permissions: ['create_expense', 'view_branch'],
    });

    await setDoc(doc(db, 'businesses/bizA/members/managerA'), {
      userId: 'managerA',
      role: 'manager',
      roleId: 'manager',
      status: 'active',
      assignedBranchIds: ['main'],
      allBranchesAccess: false,
      permissions: ['manage_staff'],
    });
    await setDoc(doc(db, 'businesses/bizA/members/branchAdmin'), {
      userId: 'branchAdmin',
      role: 'admin',
      roleId: 'admin',
      status: 'active',
      assignedBranchIds: ['main'],
      permissions: ['view_branch', 'assign_staff_to_branches'],
    });

    await setDoc(doc(db, 'businesses/bizB/members/ownerB'), {
      userId: 'ownerB',
      role: 'owner',
      roleId: 'owner',
      isOwner: true,
      status: 'active',
      assignedBranchIds: ['main'],
      allBranchesAccess: true,
    });

    await setDoc(doc(db, 'businesses/bizA/branches/main'), {
      branchId: 'main',
      businessId: 'bizA',
      name: 'Main A',
      code: 'MAIN',
      isMainBranch: true,
      status: 'active',
    });

    await setDoc(doc(db, 'businesses/bizA/branches/inactive'), {
      branchId: 'inactive',
      businessId: 'bizA',
      name: 'Inactive A',
      code: 'INACT',
      isMainBranch: false,
      status: 'inactive',
    });

    await setDoc(doc(db, 'businesses/bizA/branches/east'), {
      branchId: 'east',
      businessId: 'bizA',
      name: 'East A',
      code: 'EAST',
      isMainBranch: false,
      status: 'active',
    });

    await setDoc(doc(db, 'businesses/bizB/branches/main'), {
      branchId: 'main',
      businessId: 'bizB',
      name: 'Main B',
      code: 'MAIN',
      isMainBranch: true,
      status: 'active',
    });

    await setDoc(doc(db, 'businesses/bizA/expenses/legacy1'), {
      businessId: 'bizA',
      expenseNumber: 'EXP-LEGACY-1',
      description: 'Legacy expense without branch id',
      amountMinor: 100,
      status: 'active',
    });
  });
}

test('owner can create a branch in own business', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('ownerA').firestore();

  const write = setDoc(doc(db, 'businesses/bizA/branches/east'), {
    branchId: 'east',
    businessId: 'bizA',
    name: 'East A',
    code: 'EAST',
    isMainBranch: false,
    status: 'active',
  });

  await assertSucceeds(write);
});

test('cashier cannot create a branch', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('cashierA').firestore();

  const write = setDoc(doc(db, 'businesses/bizA/branches/west'), {
    branchId: 'west',
    businessId: 'bizA',
    name: 'West A',
    code: 'WEST',
    isMainBranch: false,
    status: 'active',
  });

  await assertFails(write);
});

test('manager cannot self-escalate role fields', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('managerA').firestore();

  const update = updateDoc(doc(db, 'businesses/bizA/members/managerA'), {
    roleId: 'owner',
    role: 'owner',
    isOwner: true,
  });

  await assertFails(update);
});

test('active member cannot read branches of another business', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('cashierA').firestore();

  const read = getDoc(doc(db, 'businesses/bizB/branches/main'));

  await assertFails(read);
});

test('owner can read branch in own business', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('ownerA').firestore();

  const read = getDoc(doc(db, 'businesses/bizA/branches/main'));
  const snapshot = await assertSucceeds(read);

  assert.equal(snapshot.exists(), true);
  assert.equal(snapshot.data().businessId, 'bizA');
});

test('cashier can create expense with active assigned branch', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('cashierA').firestore();

  const write = setDoc(doc(db, 'businesses/bizA/expenses/exp-active-branch'), {
    businessId: 'bizA',
    branchId: 'main',
    description: 'Stock room purchase',
    amountMinor: 500,
    status: 'active',
  });

  await assertSucceeds(write);
});

test('cashier cannot create expense without explicit branchId', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('cashierA').firestore();

  const write = setDoc(doc(db, 'businesses/bizA/expenses/exp-missing-branch'), {
    businessId: 'bizA',
    description: 'Branchless write attempt',
    amountMinor: 200,
    status: 'active',
  });

  await assertFails(write);
});

test('cashier cannot create expense on inactive branch', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('cashierA').firestore();

  const write = setDoc(doc(db, 'businesses/bizA/expenses/exp-inactive-branch'), {
    businessId: 'bizA',
    branchId: 'inactive',
    description: 'Inactive branch write attempt',
    amountMinor: 300,
    status: 'active',
  });

  await assertFails(write);
});

test('manager cannot create a branch without manage_branches', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('managerA').firestore();
  await assertFails(setDoc(doc(db, 'businesses/bizA/branches/west'), {
    branchId: 'west',
    businessId: 'bizA',
    name: 'West A',
    code: 'WEST',
    isMainBranch: false,
    status: 'active',
  }));
});

test('branch assignment permission can assign staff without changing role', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('branchAdmin').firestore();
  await assertSucceeds(updateDoc(doc(db, 'businesses/bizA/members/mainStaff'), {
    assignedBranchIds: ['main', 'east'],
    defaultBranchId: 'east',
  }));
  await assertFails(updateDoc(doc(db, 'businesses/bizA/members/mainStaff'), {
    roleId: 'owner',
  }));
});

test('owner creates an expense in East without branch assignment', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('ownerA').firestore();

  await assertSucceeds(
    setDoc(doc(db, 'businesses/bizA/expenses/exp-owner-east'), {
      businessId: 'bizA',
      branchId: 'east',
      description: 'East owner expense',
      amountMinor: 500,
      status: 'active',
    }),
  );
});

test('assigned staff creates East expense and unassigned staff is denied', async () => {
  await seedBusinessData();
  const eastDb = testEnv.authenticatedContext('eastStaff').firestore();
  const mainDb = testEnv.authenticatedContext('mainStaff').firestore();
  const data = {
    businessId: 'bizA',
    branchId: 'east',
    description: 'East staff expense',
    amountMinor: 500,
    status: 'active',
  };

  await assertSucceeds(
    setDoc(doc(eastDb, 'businesses/bizA/expenses/exp-east-staff'), data),
  );
  await assertFails(
    setDoc(doc(mainDb, 'businesses/bizA/expenses/exp-main-staff'), data),
  );
});

test('owner creates business-level supplier without branchId', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('ownerA').firestore();

  await assertSucceeds(
    setDoc(doc(db, 'businesses/bizA/suppliers/supplier-1'), {
      supplierId: 'supplier-1',
      businessId: 'bizA',
      name: 'Shared Supplier',
      status: 'active',
    }),
  );
});

test('supplier master cannot be created with branchId', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('ownerA').firestore();

  await assertFails(
    setDoc(doc(db, 'businesses/bizA/suppliers/supplier-east'), {
      supplierId: 'supplier-east',
      businessId: 'bizA',
      branchId: 'east',
      name: 'Incorrect Branch Supplier',
      status: 'active',
    }),
  );
});

test('cashier cannot bypass scoped collections via recursive fallback', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('cashierA').firestore();

  const write = setDoc(doc(db, 'businesses/bizA/unlisted_collection/doc1'), {
    businessId: 'bizA',
    description: 'Fallback bypass write',
    amountMinor: 111,
    status: 'active',
  });

  await assertFails(write);
});

test('cashier cannot write records in another business', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('cashierA').firestore();

  const write = setDoc(doc(db, 'businesses/bizB/sales/sale-cross-business'), {
    businessId: 'bizB',
    branchId: 'main',
    status: 'completed',
    saleStatus: 'completed',
  });

  await assertFails(write);
});

test('cashier can still read legacy branchless expense in main scope', async () => {
  await seedBusinessData();
  const db = testEnv.authenticatedContext('cashierA').firestore();

  const read = getDoc(doc(db, 'businesses/bizA/expenses/legacy1'));
  const snapshot = await assertSucceeds(read);

  assert.equal(snapshot.exists(), true);
  assert.equal(snapshot.data().businessId, 'bizA');
});
