import fs from "fs";

function loadEnv(path) {
  const env = {};
  for (const line of fs.readFileSync(path, "utf8").split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf("=");
    if (i < 0) continue;
    let v = line.slice(i + 1);
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
      v = v.slice(1, -1);
    }
    env[line.slice(0, i)] = v.replace(/\\n/g, "\n");
  }
  return env;
}

const env = loadEnv(".env.pinata.check");
const jwt = env.PINATA_JWT.trim();
const now = Math.floor(Date.now() / 1000);

const payloads = [
  {label: "expires_only", body: {expires: 30}},
  {label: "network_expires", body: {network: "public", expires: 30}},
  {
    label: "date_expires_seconds",
    body: {date: now, expires: 120},
  },
  {
    label: "full_public",
    body: {
      network: "public",
      date: now,
      expires: 120,
      max_file_size: 1500000,
      allow_mime_types: ["image/jpeg"],
      filename: "probe.jpg",
    },
  },
  {
    label: "legacy_timestamp_expires",
    body: {
      date: now,
      expires: now + 120,
      max_file_size: 1500000,
      allow_mime_types: ["image/jpeg"],
      filename: "probe.jpg",
    },
  },
];

for (const item of payloads) {
  const res = await fetch("https://uploads.pinata.cloud/v3/files/sign", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(item.body),
  });
  console.log(item.label, res.status, (await res.text()).slice(0, 250));
}

// Also try pinFileToIPFS legacy as fallback probe of write scope
const form = new FormData();
form.append(
  "file",
  new Blob([Uint8Array.from([1, 2, 3, 4])], {type: "image/jpeg"}),
  "probe.jpg",
);
const pin = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
  method: "POST",
  headers: {Authorization: `Bearer ${jwt}`},
  body: form,
});
console.log("legacy_pinFile", pin.status, (await pin.text()).slice(0, 250));

fs.unlinkSync(".env.pinata.check");
