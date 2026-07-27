import fs from "fs";

const text = fs.readFileSync(".env.pinata.check", "utf8");
const env = {};
for (const line of text.split(/\r?\n/)) {
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
  v = v.replace(/\\n/g, "\n");
  env[line.slice(0, i)] = v;
}

const g = (env.PINATA_GATEWAY || "").trim();
const jwt = (env.PINATA_JWT || "").trim();
console.log(
  JSON.stringify(
    {
      gateway: g,
      gatewayLen: g.length,
      jwtLen: jwt.length,
      jwtPrefix: jwt.slice(0, 15),
      jwtLooksJwt: jwt.split(".").length === 3,
      isReplaceMe: jwt === "REPLACE_ME" || g === "REPLACE_ME",
    },
    null,
    2,
  ),
);

const auth = await fetch("https://api.pinata.cloud/data/testAuthentication", {
  headers: {Authorization: `Bearer ${jwt}`},
});
console.log("pinata_auth_status", auth.status, (await auth.text()).slice(0, 200));

const now = Math.floor(Date.now() / 1000);
const signWrong = await fetch("https://uploads.pinata.cloud/v3/files/sign", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${jwt}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    date: now,
    expires: now + 120,
    max_file_size: 1500000,
    allow_mime_types: ["image/jpeg"],
    filename: "probe.jpg",
  }),
});
console.log(
  "sign_wrong_expires",
  signWrong.status,
  (await signWrong.text()).slice(0, 300),
);

const signRight = await fetch("https://uploads.pinata.cloud/v3/files/sign", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${jwt}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    network: "public",
    date: now,
    expires: 120,
    max_file_size: 1500000,
    allow_mime_types: ["image/jpeg", "image/*"],
    filename: "probe.jpg",
  }),
});
const signRightText = await signRight.text();
console.log("sign_right_expires", signRight.status, signRightText.slice(0, 400));

fs.unlinkSync(".env.pinata.check");
