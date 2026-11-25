"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { apiFetch } from "@/lib/api-client";
import { clearToken, readToken, useAuthToken } from "@/lib/auth-token";
import type { CurrentUser, UserRoleName } from "@/types/auth";

const ROLE_LABELS: Record<UserRoleName, string> = {
  owner: "Chủ chuỗi",
  branch_manager: "Quản lý chi nhánh",
  staff: "Nhân viên",
  customer: "Khách hàng",
};

/** Thông tin người đang đăng nhập. Chưa đăng nhập (hoặc token hết hạn/bị từ chối) thì về trang đăng nhập. */
export function CurrentUserPanel() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const token = useAuthToken();

  // Đọc thẳng localStorage thay vì `token`: lần render đầu (hydrate) `token` luôn là null.
  useEffect(() => {
    if (!readToken()) router.replace("/login");
  }, [token, router]);

  const me = useQuery({
    queryKey: ["auth", "me", token],
    queryFn: () => apiFetch<CurrentUser>("/auth/me"),
    enabled: token !== null,
  });

  function logout() {
    clearToken();
    queryClient.clear();
    router.replace("/login");
  }

  if (!me.data) {
    return (
      <section className="flex flex-col gap-4 border border-hairline bg-white p-6">
        {me.isError ? (
          <>
            <p role="alert" className="text-sm text-signal">
              {me.error.message}
            </p>
            <div className="flex gap-3">
              <Button onClick={() => void me.refetch()}>Thử lại</Button>
              <Button variant="outline" onClick={logout}>
                Đăng xuất
              </Button>
            </div>
          </>
        ) : (
          <>
            <Skeleton className="h-7 w-56" />
            <Skeleton className="h-5 w-72" />
            <Skeleton className="h-16 w-full" />
            <p role="status" className="text-sm text-neutral-600">
              Đang kết nối máy chủ Basement...
            </p>
          </>
        )}
      </section>
    );
  }

  const user = me.data;
  return (
    <section className="flex flex-col gap-6 border border-hairline bg-white p-6">
      <div className="flex flex-col gap-1">
        <p className="font-mono text-xs text-neutral-600">/ 01 Tài khoản</p>
        <h1 className="text-2xl font-bold">Xin chào, {user.fullName ?? user.email ?? user.phone}</h1>
        <p className="text-sm text-neutral-600">
          {[user.email, user.phone].filter(Boolean).join(" · ")} ·{" "}
          <span className="font-mono">{user.memberCode}</span>
        </p>
      </div>

      <div className="flex flex-col gap-2">
        <p className="font-mono text-xs text-neutral-600">/ 02 Vai trò</p>
        {user.roles.length === 0 ? (
          <p className="text-sm text-neutral-600">Tài khoản chưa được gán vai trò nào.</p>
        ) : (
          <ul className="flex flex-wrap gap-2">
            {user.roles.map((role) => (
              <li
                key={`${role.role}-${role.branch?.id ?? "all"}`}
                className="inline-flex items-center gap-2 rounded-full border border-hairline bg-concrete px-3 py-1 text-sm"
              >
                <span className="font-semibold">{ROLE_LABELS[role.role]}</span>
                <span className="font-mono text-xs text-neutral-600">
                  {role.branch ? `[${role.branch.code}] ${role.branch.name}` : "[Toàn chuỗi]"}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div>
        <Button variant="outline" onClick={logout}>
          Đăng xuất
        </Button>
      </div>
    </section>
  );
}
