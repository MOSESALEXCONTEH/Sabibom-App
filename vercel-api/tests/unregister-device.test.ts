import type {VercelRequest, VercelResponse} from "@vercel/node";
import {beforeEach, describe, expect, it, vi} from "vitest";
import {errors} from "../src/utils/api-errors";

const mocks = vi.hoisted(() => ({
  authenticateRequest: vi.fn(),
  enforceRateLimit: vi.fn(),
  userSet: vi.fn(),
  deviceSet: vi.fn(),
  get: vi.fn(),
  collection: vi.fn(),
}));

vi.mock("../src/middleware/authenticate-request", () => ({
  authenticateRequest: mocks.authenticateRequest,
}));
vi.mock("../src/middleware/rate-limit", () => ({
  enforceRateLimit: mocks.enforceRateLimit,
}));
vi.mock("../src/config/firebase-admin", () => ({
  adminFirestore: () => ({collection: mocks.collection}),
}));
vi.mock("firebase-admin/firestore", () => ({
  FieldValue: {
    arrayRemove: vi.fn(() => "array-remove"),
    serverTimestamp: vi.fn(() => "server-timestamp"),
  },
}));

import unregisterDevice from "../src/http/notifications/unregister-device";

const token = "fcm-token-which-is-long-enough-for-validation";

function response(): VercelResponse & {body?: unknown} {
  const result = {
    status: vi.fn(),
    setHeader: vi.fn(),
    json: vi.fn(),
  } as unknown as VercelResponse & {body?: unknown};
  vi.mocked(result.status).mockReturnValue(result);
  vi.mocked(result.setHeader).mockReturnValue(result);
  vi.mocked(result.json).mockImplementation((body: unknown) => {
    result.body = body;
    return result;
  });
  return result;
}

function request(body: Record<string, unknown>, authorization = "Bearer valid") {
  return {
    method: "POST",
    headers: {authorization},
    body,
  } as unknown as VercelRequest;
}

describe("unregister-device", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.authenticateRequest.mockResolvedValue({uid: "owner-uid"});
    mocks.enforceRateLimit.mockResolvedValue(undefined);
    mocks.get.mockResolvedValue({docs: []});
    mocks.collection.mockImplementation((name: string) => {
      expect(name).toBe("users");
      return {
        doc: (uid: string) => {
          expect(uid).toBe("owner-uid");
          return {
            set: mocks.userSet,
            collection: (child: string) => {
              expect(child).toBe("devices");
              return {where: () => ({get: mocks.get})};
            },
          };
        },
      };
    });
  });

  it("disables matching devices owned by the authenticated user and removes legacy tokens", async () => {
    mocks.get.mockResolvedValue({docs: [{ref: {set: mocks.deviceSet}}]});
    const res = response();
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});

    await unregisterDevice(request({token, platform: "android", uid: "other-user"}), res);

    expect(mocks.authenticateRequest).toHaveBeenCalledOnce();
    expect(mocks.deviceSet).toHaveBeenCalledWith(
      expect.objectContaining({isActive: false, notificationsEnabled: false}),
      {merge: true},
    );
    expect(mocks.userSet).toHaveBeenCalledWith(
      expect.objectContaining({fcmTokens: "array-remove"}),
      {merge: true},
    );
    expect(res.body).toEqual({success: true, data: {disabled: true}});
    expect(JSON.stringify(res.body)).not.toContain(token);
    expect(consoleError).not.toHaveBeenCalled();
    consoleError.mockRestore();
  });

  it("returns 401 without authenticating a request", async () => {
    mocks.authenticateRequest.mockRejectedValue(errors.unauthenticated("nope"));
    const res = response();

    await unregisterDevice(request({token, platform: "ios"}), res);

    expect(res.status).toHaveBeenCalledWith(401);
    expect(res.body).toEqual({
      success: false,
      error: {code: "unauthenticated", message: "nope"},
    });
  });

  it("is idempotent when the token is already disabled or absent", async () => {
    const res = response();

    await unregisterDevice(request({token, platform: "android"}), res);

    expect(mocks.userSet).toHaveBeenCalledOnce();
    expect(res.body).toEqual({success: true, data: {disabled: false}});
  });
});