import {App, cert, getApps, initializeApp} from "firebase-admin/app";
import {Auth, getAuth} from "firebase-admin/auth";
import {Firestore, getFirestore} from "firebase-admin/firestore";
import {getEnv} from "./env";

let app: App | undefined;

function getAdminApp(): App {
  if (app) return app;
  const existing = getApps()[0];
  if (existing) {
    app = existing;
    return app;
  }

  const env = getEnv();
  app = initializeApp({
    credential: cert({
      projectId: env.firebaseProjectId,
      clientEmail: env.firebaseClientEmail,
      privateKey: env.firebasePrivateKey,
    }),
    projectId: env.firebaseProjectId,
  });
  return app;
}

export function adminAuth(): Auth {
  return getAuth(getAdminApp());
}

export function adminFirestore(): Firestore {
  return getFirestore(getAdminApp());
}
