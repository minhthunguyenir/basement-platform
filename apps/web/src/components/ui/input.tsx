import type { InputHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

/** Ô nhập liệu viền mảnh, bo nhẹ. Viết theo API của shadcn/ui, chưa sinh bằng shadcn CLI. */
export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "h-11 w-full rounded-[4px] border border-hairline bg-white px-3 text-base text-ink",
        "placeholder:text-neutral-600/70 focus:border-ink focus:outline-none",
        "disabled:cursor-not-allowed disabled:bg-concrete",
        className,
      )}
      {...props}
    />
  );
}
