import {describe, expect, it} from "vitest";
import {ApiError, errors} from "../src/utils/api-errors";

describe("api errors", () => {
  it("maps unauthenticated to 401", () => {
    const error = errors.unauthenticated();
    expect(error).toBeInstanceOf(ApiError);
    expect(error.status).toBe(401);
    expect(error.code).toBe("unauthenticated");
  });

  it("maps permission denied to 403", () => {
    const error = errors.permissionDenied();
    expect(error.status).toBe(403);
  });

  it("maps rate limited to 429", () => {
    const error = errors.rateLimited();
    expect(error.status).toBe(429);
  });
});
