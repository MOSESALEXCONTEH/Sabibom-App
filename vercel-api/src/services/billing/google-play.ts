import {createHash} from "node:crypto";
import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {JWT} from "google-auth-library";
import {getEnv} from "../../config/env";
import {errors} from "../../utils/api-errors";
import {entitlementsForTier} from "./entitlements";

type GooglePlaySubscription = {
  subscriptionState?: string;
  acknowledgementState?: string;
  linkedPurchaseToken?: string;
  startTime?: string;
  lineItems?: Array<{
    productId?: string;
    expiryTime?: string;
    autoRenewingPlan?: {autoRenewEnabled?: boolean};
  }>;
};

export type VerifiedGooglePlaySubscription = {
  productId: string;
  status: string;
  startedAt: Date | null;
  currentPeriodEnd: Date;
  cancelAtPeriodEnd: boolean;
  acknowledgementPending: boolean;
  linkedPurchaseTokenHash: string | null;
};

export function purchaseTokenHash(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function normalizeGooglePlaySubscription(
  value: GooglePlaySubscription,
  expectedProductId: string,
): VerifiedGooglePlaySubscription {
  const matching = value.lineItems?.filter((item) => item.productId === expectedProductId) ?? [];
  if (matching.length === 0) {
    throw errors.invalidArgument("The Google Play purchase does not match this plan.");
  }
  const expiry = matching
    .map((item) => item.expiryTime ? new Date(item.expiryTime) : null)
    .filter((date): date is Date => date !== null && !Number.isNaN(date.getTime()))
    .sort((a, b) => b.getTime() - a.getTime())[0];
  if (!expiry) throw errors.invalidArgument("Google Play did not return a valid subscription period.");

  const state = value.subscriptionState ?? "SUBSCRIPTION_STATE_UNSPECIFIED";
  const status = (() => {
    switch (state) {
      case "SUBSCRIPTION_STATE_ACTIVE": return "active";
      case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD": return "grace_period";
      case "SUBSCRIPTION_STATE_CANCELED": return "canceled";
      case "SUBSCRIPTION_STATE_PAUSED": return "paused";
      case "SUBSCRIPTION_STATE_ON_HOLD": return "past_due";
      case "SUBSCRIPTION_STATE_EXPIRED": return "expired";
      case "SUBSCRIPTION_STATE_PENDING": return "pending";
      default: return "not_configured";
    }
  })();
  const start = value.startTime ? new Date(value.startTime) : null;
  return {
    productId: expectedProductId,
    status,
    startedAt: start && !Number.isNaN(start.getTime()) ? start : null,
    currentPeriodEnd: expiry,
    cancelAtPeriodEnd:
      state === "SUBSCRIPTION_STATE_CANCELED" ||
      matching.every((item) => item.autoRenewingPlan?.autoRenewEnabled === false),
    acknowledgementPending:
      value.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    linkedPurchaseTokenHash: value.linkedPurchaseToken
      ? purchaseTokenHash(value.linkedPurchaseToken)
      : null,
  };
}

class GooglePlayClient {
  private async accessToken(): Promise<string> {
    const env = getEnv();
    const jwt = new JWT({
      email: env.googlePlayClientEmail,
      key: env.googlePlayPrivateKey,
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    });
    const credentials = await jwt.authorize();
    if (!credentials.access_token) throw errors.unavailable("Google Play verification is unavailable.");
    return credentials.access_token;
  }

  async getSubscription(purchaseToken: string): Promise<GooglePlaySubscription> {
    const env = getEnv();
    const token = await this.accessToken();
    const url = new URL(
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(env.googlePlayPackageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
    );
    const response = await fetch(url, {headers: {Authorization: `Bearer ${token}`}});
    if (!response.ok) {
      console.error("[sabibom-api] Google Play verification failed", {status: response.status});
      throw response.status === 404
        ? errors.invalidArgument("Google Play could not verify this purchase.")
        : errors.unavailable("Google Play verification is temporarily unavailable.");
    }
    return await response.json() as GooglePlaySubscription;
  }

  async acknowledge(productId: string, purchaseToken: string): Promise<void> {
    const env = getEnv();
    const token = await this.accessToken();
    const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(env.googlePlayPackageName)}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
    const response = await fetch(url, {
      method: "POST",
      headers: {Authorization: `Bearer ${token}`, "Content-Type": "application/json"},
      body: "{}",
    });
    if (!response.ok && response.status !== 409) {
      console.error("[sabibom-api] Google Play acknowledgement failed", {status: response.status});
      throw errors.unavailable("The purchase was verified but could not be acknowledged yet.");
    }
  }
}

export async function verifyAndPersistGooglePlaySubscription(input: {
  db: Firestore;
  businessId: string;
  uid: string;
  productId: string;
  purchaseToken: string;
  client?: GooglePlayClient;
}): Promise<VerifiedGooglePlaySubscription> {
  const tokenHash = purchaseTokenHash(input.purchaseToken);
  const ledgerRef = input.db.collection("billing_purchase_tokens").doc(tokenHash);
  const existing = await ledgerRef.get();
  if (existing.exists && existing.data()?.businessId !== input.businessId) {
    throw errors.permissionDenied("This Google Play purchase is already linked to another business.");
  }

  const planQuery = await input.db
    .collection("subscription_plans")
    .where("googlePlayProductId", "==", input.productId)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (planQuery.empty) throw errors.invalidArgument("This Google Play product is not linked to an active plan.");
  const plan = planQuery.docs[0];
  const planData = plan.data();
  const client = input.client ?? new GooglePlayClient();
  const remote = await client.getSubscription(input.purchaseToken);
  const verified = normalizeGooglePlaySubscription(remote, input.productId);
  const now = FieldValue.serverTimestamp();
  const subscriptionRef = input.db.collection("business_subscriptions").doc(input.businessId);
  const businessRef = input.db.collection("businesses").doc(input.businessId);
  const eventRef = input.db.collection("billing_events").doc();
  const entitlementsRef = input.db.collection("business_entitlements").doc(input.businessId);
  const batch = input.db.batch();
  const subscriptionRecord = {
    subscriptionId: input.businessId,
    businessId: input.businessId,
    planId: plan.id,
    accessType: "paid",
    provider: "google_play",
    providerReference: tokenHash,
    googlePlayProductId: input.productId,
    googlePlayPurchaseTokenHash: tokenHash,
    status: verified.status,
    startedAt: verified.startedAt,
    currentPeriodStart: verified.startedAt,
    currentPeriodEnd: verified.currentPeriodEnd,
    cancelAtPeriodEnd: verified.cancelAtPeriodEnd,
    updatedAt: now,
  };
  batch.set(subscriptionRef, {...subscriptionRecord, createdAt: now}, {merge: true});
  batch.set(ledgerRef, {
    tokenHash,
    businessId: input.businessId,
    userId: input.uid,
    productId: input.productId,
    planId: plan.id,
    linkedPurchaseTokenHash: verified.linkedPurchaseTokenHash,
    updatedAt: now,
    createdAt: existing.exists ? existing.data()?.createdAt ?? now : now,
  }, {merge: true});
  batch.set(businessRef, {subscription: subscriptionRecord, updatedAt: now}, {merge: true});
  batch.set(eventRef, {
    eventId: eventRef.id,
    type: "google_play_subscription_verified",
    provider: "google_play",
    businessId: input.businessId,
    subscriptionId: input.businessId,
    productId: input.productId,
    status: "processed",
    createdAt: now,
    updatedAt: now,
  });
  const tier = planData.tier === "free" ? "free" : "pro";
  batch.set(entitlementsRef, {
    businessId: input.businessId,
    tier,
    values: entitlementsForTier(tier, planData.limits),
    source: "google_play",
    schemaVersion: 1,
    updatedAt: now,
  }, {merge: true});
  await batch.commit();
  if (verified.acknowledgementPending) {
    await client.acknowledge(input.productId, input.purchaseToken);
  }
  return verified;
}
