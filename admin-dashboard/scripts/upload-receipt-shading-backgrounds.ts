import fs from "node:fs/promises";
import path from "node:path";
import { FieldValue } from "firebase-admin/firestore";
import { adminFirestore, adminStorageBucket } from "../src/lib/firebase/admin";

type Candidate = {
  fileName: string;
  fullPath: string;
};

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function prettyName(fileName: string): string {
  const base = fileName.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim();
  if (!base) return "Shading";
  return base
    .split(" ")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

async function collectImages(dir: string): Promise<Candidate[]> {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = entries
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => /\.(png|jpg|jpeg|webp)$/i.test(name))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));

  return files.map((fileName) => ({
    fileName,
    fullPath: path.join(dir, fileName),
  }));
}

async function main() {
  // Safety gate for one-off script execution.
  if (process.env.UPLOAD_ALLOW !== "true") {
    throw new Error(
      "Upload refused: set UPLOAD_ALLOW=true to run this script intentionally.",
    );
  }

  required("FIREBASE_PROJECT_ID");
  required("FIREBASE_CLIENT_EMAIL");
  required("FIREBASE_PRIVATE_KEY");

  const sourceDir = path.resolve(
    process.cwd(),
    process.env.SHADING_SOURCE_DIR ?? "../assets/Shading background",
  );
  const storagePrefix =
    process.env.SHADING_STORAGE_PREFIX?.trim() || "receipt_shading/backgrounds";

  const candidates = await collectImages(sourceDir);
  if (candidates.length == 0) {
    throw new Error(
      `No image files found in ${sourceDir}. Add png/jpg/jpeg/webp files and retry.`,
    );
  }

  const db = adminFirestore();
  const bucket = adminStorageBucket();

  console.log(`Uploading ${candidates.length} shading images from: ${sourceDir}`);
  console.log(`Storage prefix: ${storagePrefix}`);

  let sortOrder = 10;
  for (const candidate of candidates) {
    const storagePath = `${storagePrefix}/${candidate.fileName}`;
    const storageFile = bucket.file(storagePath);

    const contentType = candidate.fileName.toLowerCase().endsWith(".png")
      ? "image/png"
      : candidate.fileName.toLowerCase().endsWith(".webp")
        ? "image/webp"
        : "image/jpeg";

    const bytes = await fs.readFile(candidate.fullPath);
    await storageFile.save(bytes, {
      resumable: false,
      metadata: {
        contentType,
        cacheControl: "public, max-age=31536000, immutable",
      },
    });

    // Keep private/public control in Firebase rules; app can resolve URLs
    // from storagePath. We also save imageUrl when available for flexibility.
    let imageUrl = "";
    try {
      imageUrl = await storageFile.getSignedUrl({
        action: "read",
        expires: "03-01-2500",
      }).then((result) => result[0]);
    } catch {
      imageUrl = "";
    }

    const id = candidate.fileName
      .replace(/\.[^.]+$/, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "");

    await db.collection("receipt_shading_backgrounds").doc(id).set(
      {
        name: prettyName(candidate.fileName),
        storagePath,
        imageUrl,
        thumbnailUrl: imageUrl,
        isActive: true,
        isPremium: false,
        sortOrder,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    sortOrder += 10;
    console.log(`Uploaded and indexed: ${candidate.fileName} -> ${storagePath}`);
  }

  console.log("Done. Cloud shading backgrounds are now available in app.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
