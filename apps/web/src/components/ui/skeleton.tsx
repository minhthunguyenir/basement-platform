import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

/** Khối giữ chỗ khi đang tải (FRONTEND_RULES mục 4). */
export function Skeleton({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div aria-hidden className={cn("animate-pulse rounded-[4px] bg-concrete", className)} {...props} />;
}
