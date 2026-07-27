import fs from "fs";
import path from "path";
import https from "https";

const PROJECT = "sabibom-app";
const SA_EMAIL = "firebase-adminsdk-fbsvc@sabibom-app.iam.gserviceaccount.com";
const cfgPath = path.join(
  process.env.USERPROFILE,
  ".config",
  "configstore",
  "firebase-tools.json",
);
const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
const access = cfg.tokens?.access_token;
if (!access) {
  console.error("NO_ACCESS_TOKEN");
  process.exit(1);
}

function request(method, url, headers = {}, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = https.request(
      {
        method,
        hostname: u.hostname,
        path: u.pathname + u.search,
        headers: {
          ...headers,
          ...(body
            ? {
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(body),
              }
            : {}),
        },
      },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => resolve({status: res.statusCode, body: data}));
      },
    );
    req.on("error", reject);
    if (body) req.write(body);
    req.end();
  });
}

const createBody = JSON.stringify({keyAlgorithm: "KEY_ALG_RSA_2048"});
const created = await request(
  "POST",
  `https://iam.googleapis.com/v1/projects/${PROJECT}/serviceAccounts/${SA_EMAIL}/keys`,
  {Authorization: `Bearer ${access}`},
  createBody,
);

if (created.status >= 300) {
  console.error("CREATE_KEY_FAILED", created.status, created.body.slice(0, 500));
  process.exit(1);
}

const createdJson = JSON.parse(created.body);
const privateKeyData = createdJson.privateKeyData;
if (!privateKeyData) {
  console.error("NO_PRIVATE_KEY_DATA");
  process.exit(1);
}

const sa = JSON.parse(Buffer.from(privateKeyData, "base64").toString("utf8"));
const outDir = path.join(process.env.TEMP, "sabibom-firebase-sa");
fs.mkdirSync(outDir, {recursive: true});
const outPath = path.join(outDir, "sa.json");
fs.writeFileSync(outPath, JSON.stringify(sa, null, 2), {
  encoding: "utf8",
  mode: 0o600,
});

console.log(
  JSON.stringify(
    {
      ok: true,
      outPath,
      project_id: sa.project_id,
      client_email: sa.client_email,
      private_key_has_begin: String(sa.private_key).includes("BEGIN PRIVATE KEY"),
      private_key_lines: String(sa.private_key).split("\n").length,
    },
    null,
    2,
  ),
);
