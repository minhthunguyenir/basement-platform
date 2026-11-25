import { CurrentUserPanel } from "@/components/features/auth/CurrentUserPanel";

export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-7xl flex-1 flex-col gap-6 px-4 py-10 sm:px-6">
      <header className="flex items-baseline justify-between border-b border-hairline pb-4">
        <span className="text-lg font-bold">Basement</span>
        <span className="font-mono text-xs text-neutral-600">/ Trang chủ</span>
      </header>
      <CurrentUserPanel />
    </main>
  );
}
