import type { Metadata } from "next";
import { LoginForm } from "@/components/features/auth/LoginForm";

export const metadata: Metadata = {
  title: "Đăng nhập · Basement",
};

export default function LoginPage() {
  return (
    <main className="bg-blueprint-grid flex flex-1 items-center justify-center px-4 py-12">
      <div className="w-full max-w-sm border border-hairline bg-white p-8">
        <p className="font-mono text-xs text-neutral-600">/ BASEMENT</p>
        <h1 className="mt-2 text-2xl font-bold">Đăng nhập</h1>
        <p className="mt-1 mb-6 text-sm text-neutral-600">Dùng email hoặc số điện thoại đã đăng ký.</p>
        <LoginForm />
      </div>
    </main>
  );
}
