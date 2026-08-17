import {FieldPath} from "firebase-admin/firestore";
import {adminFirestore} from "../src/config/firebase-admin";
import {materializeBusinessEntitlements} from "../src/services/billing/entitlements";

async function main(): Promise<void> {
  const apply = process.argv.includes("--apply");
  const db = adminFirestore();
  let lastId: string | null = null;
  let inspected = 0;
  let written = 0;

  while (true) {
    let query = db.collection("businesses").orderBy(FieldPath.documentId()).limit(100);
    if (lastId) query = query.startAfter(lastId);
    const page = await query.get();
    if (page.empty) break;
    for (const document of page.docs) {
      inspected += 1;
      if (apply) {
        await materializeBusinessEntitlements({db, businessId: document.id});
        written += 1;
      }
    }
    lastId = page.docs.at(-1)?.id ?? null;
    if (page.size < 100) break;
  }

  console.log(JSON.stringify({mode: apply ? "apply" : "dry-run", inspected, written}));
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : "Billing entitlement migration failed.");
  process.exitCode = 1;
});
