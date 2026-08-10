"use client";

import { FormEvent, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  GoogleAuthProvider,
  signInWithEmailAndPassword,
  signInWithPopup,
} from "firebase/auth";
import { getClientAuth } from "@/lib/firebase/client";

export function LoginForm() {
  const router = useRouter();
  const search = useSearchParams();
  const next = search.get("next") || "/dashboard";
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function establishSession(idToken: string) {
    const res = await fetch("/api/admin/session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken }),
    });
    const payload = await res.json().catch(() => null);
    if (!res.ok) {
      const code = payload?.error?.code as string | undefined;
      if (code === "not_platform_admin" || code === "admin_disabled") {
        router.replace("/unauthorized");
        return;
      }
      throw new Error(
        payload?.error?.message || "Could not create an admin session.",
      );
    }
    router.replace(next.startsWith("/") ? next : "/dashboard");
    router.refresh();
  }

  async function onEmailSubmit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const cred = await signInWithEmailAndPassword(
        getClientAuth(),
        email.trim(),
        password,
      );
      const idToken = await cred.user.getIdToken(true);
      await establishSession(idToken);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Sign-in failed.");
    } finally {
      setBusy(false);
    }
  }

  async function onGoogle() {
    setBusy(true);
    setError(null);
    try {
      const provider = new GoogleAuthProvider();
      const cred = await signInWithPopup(getClientAuth(), provider);
      const idToken = await cred.user.getIdToken(true);
      await establishSession(idToken);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Google sign-in failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto w-full max-w-md rounded-2xl border border-surface-border bg-white p-8 shadow-sm">
      <p className="text-xs font-semibold uppercase tracking-wide text-brand">
        SabiBom
      </p>
      <h1 className="mt-1 text-2xl font-bold text-slate-900">
        Super Admin sign-in
      </h1>
      <p className="mt-2 text-sm text-slate-600">
        Platform administrators only. Business owners are not granted access
        automatically.
      </p>

      <form onSubmit={onEmailSubmit} className="mt-6 space-y-4">
        <label className="block text-sm font-medium text-slate-700">
          Email
          <input
            type="email"
            autoComplete="username"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 w-full rounded-lg border border-surface-border px-3 py-2 text-sm outline-none focus:border-brand"
          />
        </label>
        <label className="block text-sm font-medium text-slate-700">
          Password
          <input
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="mt-1 w-full rounded-lg border border-surface-border px-3 py-2 text-sm outline-none focus:border-brand"
          />
        </label>
        {error && (
          <p role="alert" className="text-sm text-red-600">
            {error}
          </p>
        )}
        <button
          type="submit"
          disabled={busy}
          className="w-full rounded-lg bg-brand px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-dark disabled:opacity-60"
        >
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>

      <div className="my-4 flex items-center gap-3 text-xs text-slate-400">
        <div className="h-px flex-1 bg-surface-border" />
        or
        <div className="h-px flex-1 bg-surface-border" />
      </div>

      <button
        type="button"
        onClick={onGoogle}
        disabled={busy}
        className="w-full rounded-lg border border-surface-border bg-white px-4 py-2.5 text-sm font-semibold text-slate-800 hover:bg-surface-muted disabled:opacity-60"
      >
        Continue with Google
      </button>
    </div>
  );
}
