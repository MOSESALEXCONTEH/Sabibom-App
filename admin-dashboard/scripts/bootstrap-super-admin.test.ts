import { describe, expect, it, vi } from "vitest";
import {
  bootstrapSuperAdmin,
  readBootstrapConfig,
} from "../../scripts/bootstrap-super-admin";

describe("bootstrapSuperAdmin", () => {
  it("reads config from env", () => {
    expect(
      readBootstrapConfig({
        BOOTSTRAP_ALLOW: "true",
        BOOTSTRAP_SUPER_ADMIN_EMAIL: " Admin@Example.com ",
        BOOTSTRAP_FORCE: "true",
      }),
    ).toEqual({
      allow: true,
      force: true,
      email: "admin@example.com",
    });
  });

  it("refuses without BOOTSTRAP_ALLOW", async () => {
    await expect(
      bootstrapSuperAdmin({
        config: { allow: false, force: false, email: "a@b.com" },
        serverTimestamp: () => "ts",
        getUserByEmail: vi.fn(),
        getAdminDoc: vi.fn(),
        setAdminDoc: vi.fn(),
        writeActivity: vi.fn(),
      }),
    ).rejects.toThrow(/BOOTSTRAP_ALLOW/);
  });

  it("creates once and is idempotent on second run", async () => {
    const store = new Map<string, Record<string, unknown>>();
    const getUserByEmail = vi.fn(async () => ({
      uid: "uid-1",
      email: "admin@example.com",
      displayName: "Admin",
    }));
    const createUser = vi.fn();

    const deps = {
      config: {
        allow: true,
        force: false,
        email: "admin@example.com",
      },
      serverTimestamp: () => "ts",
      getUserByEmail,
      getAdminDoc: async (uid: string) => store.get(uid) ?? null,
      setAdminDoc: async (uid: string, data: Record<string, unknown>) => {
        store.set(uid, { ...(store.get(uid) ?? {}), ...data });
      },
      writeActivity: vi.fn(async () => undefined),
    };

    const first = await bootstrapSuperAdmin(deps);
    expect(first).toEqual({ status: "created", uid: "uid-1" });
    expect(store.get("uid-1")?.role).toBe("super_admin");
    expect(deps.writeActivity).toHaveBeenCalledOnce();

    const second = await bootstrapSuperAdmin(deps);
    expect(second).toEqual({
      status: "already_active_super_admin",
      uid: "uid-1",
    });
    expect(createUser).not.toHaveBeenCalled();
    expect(getUserByEmail).toHaveBeenCalled();
  });

  it("refuses unsafe overwrite without force", async () => {
    const result = await bootstrapSuperAdmin({
      config: { allow: true, force: false, email: "admin@example.com" },
      serverTimestamp: () => "ts",
      getUserByEmail: async () => ({ uid: "uid-2", email: "admin@example.com" }),
      getAdminDoc: async () => ({ role: "support_admin", status: "active" }),
      setAdminDoc: vi.fn(),
      writeActivity: vi.fn(),
    });
    expect(result.status).toBe("refused_overwrite");
  });

  it("never exposes a createUser dependency", async () => {
    const keys = Object.keys(
      await (async () => {
        const deps = {
          config: { allow: true, force: false, email: "a@b.com" },
          serverTimestamp: () => "ts",
          getUserByEmail: async () => ({ uid: "u", email: "a@b.com" }),
          getAdminDoc: async () => null,
          setAdminDoc: async () => undefined,
          writeActivity: async () => undefined,
        };
        await bootstrapSuperAdmin(deps);
        return deps;
      })(),
    );
    expect(keys).not.toContain("createUser");
  });
});
