"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ApiError, apiFetch } from "@/lib/api-client";
import { readToken, saveToken } from "@/lib/auth-token";
import type { LoginRequest, LoginResponse } from "@/types/auth";

/** Sau ngần này mà máy chủ chưa trả lời thì nhiều khả năng Render đang khởi động lại. */
const SLOW_RESPONSE_MS = 4000;

function loginErrorMessage(error: Error): string {
  if (!(error instanceof ApiError)) return "Đã có lỗi xảy ra, vui lòng thử lại.";
  if (error.status === 401) return "Sai email/số điện thoại hoặc mật khẩu.";
  if (error.status === 400) return "Vui lòng nhập email/số điện thoại và mật khẩu.";
  return error.message; // 429 và lỗi mạng: dùng thông báo của API / api-client.
}

export function LoginForm() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [login, setLogin] = useState("");
  const [password, setPassword] = useState("");
  const [slow, setSlow] = useState(false);

  // Đã đăng nhập rồi thì không cần ở trang này.
  useEffect(() => {
    if (readToken()) router.replace("/");
  }, [router]);

  const mutation = useMutation({
    mutationFn: (body: LoginRequest) =>
      apiFetch<LoginResponse>("/auth/login", { method: "POST", body, auth: false }),
    onSuccess: (result) => {
      queryClient.clear(); // bỏ dữ liệu của phiên trước (nếu có)
      saveToken(result.accessToken, result.expiresIn);
      router.replace("/");
    },
  });

  useEffect(() => {
    if (!mutation.isPending) return;
    const timer = setTimeout(() => setSlow(true), SLOW_RESPONSE_MS);
    return () => clearTimeout(timer);
  }, [mutation.isPending]);
  const showSlowNotice = slow && mutation.isPending;

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSlow(false);
    mutation.mutate({ login: login.trim(), password });
  }

  return (
    <form onSubmit={handleSubmit} noValidate className="flex flex-col gap-5">
      <label className="flex flex-col gap-2">
        <span className="text-sm font-semibold">Email hoặc số điện thoại</span>
        <Input
          name="login"
          autoComplete="username"
          inputMode="email"
          placeholder="vd. staff.hcm@basement.local"
          value={login}
          onChange={(event) => setLogin(event.target.value)}
          disabled={mutation.isPending}
          required
        />
      </label>

      <label className="flex flex-col gap-2">
        <span className="text-sm font-semibold">Mật khẩu</span>
        <Input
          name="password"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          disabled={mutation.isPending}
          required
        />
      </label>

      {mutation.isError && (
        <p role="alert" className="rounded-[4px] border border-signal/40 bg-signal/5 px-3 py-2 text-sm text-signal">
          {loginErrorMessage(mutation.error)}
        </p>
      )}

      <Button type="submit" disabled={mutation.isPending || !login.trim() || !password} className="mt-1 w-full">
        {mutation.isPending ? "Đang đăng nhập…" : "Đăng nhập"}
      </Button>

      {showSlowNotice && (
        <p role="status" className="text-center text-sm text-neutral-600">
          Đang kết nối máy chủ Basement... Lần đầu có thể mất 30–50 giây khi máy chủ khởi động lại.
        </p>
      )}
    </form>
  );
}
