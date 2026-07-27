import fs from "fs";
import path from "path";
import {spawnSync} from "child_process";
import {cert, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";

const saPath = path.join(process.env.TEMP, "sabibom-firebase-sa", "sa.json");
const sa = JSON.parse(fs.readFileSync(saPath, "utf8"));

// Validate key parses before uploading.
if (!getApps().length) {
  initializeApp({
    credential: cert({
      projectId: sa.project_id,
      clientEmail: sa.client_email,
      privateKey: sa.private_key,
    }),
    projectId: sa.project_id,
  });
}
await getAuth().createCustomToken("env-upload-probe");
console.log("local_key_ok");

// Single-escaped newlines for Vercel; env.ts converts \\n -> real newlines.
const privateKeyForVercel = String(sa.private_key)
  .replace(/\r\n/g, "\n")
  .replace(/\n/g, "\\n");

const pairs = [
  ["FIREBASE_PROJECT_ID", sa.project_id],
  ["FIREBASE_CLIENT_EMAIL", sa.client_email],
  ["FIREBASE_PRIVATE_KEY", privateKeyForVercel],
];
const envs = ["production", "preview", "development"];

function run(cmd, args, input) {
  const res = spawnSync(cmd, args, {
    input,
    encoding: "utf8",
    shell: process.platform === "win32",
  });
  return {
    status: res.status,
    stdout: (res.stdout || "").trim(),
    stderr: (res.stderr || "").trim(),
  };
}

for (const [name, value] of pairs) {
  for (const envName of envs) {
    console.log(`rm ${name} ${envName}`);
    run("npx", ["vercel", "env", "rm", name, envName, "--yes"]);
    console.log(`add ${name} ${envName}`);
    const added = run(
      "npx",
      ["vercel", "env", "add", name, envName],
      `${value}\n`,
    );
    if (added.status !== 0) {
      console.error("FAILED", name, envName, added.stdout, added.stderr);
      process.exit(1);
    }
  }
}

fs.unlinkSync(saPath);
try {
  fs.rmdirSync(path.dirname(saPath));
} catch {
  // ignore
}
console.log("upload_done_key_deleted");
