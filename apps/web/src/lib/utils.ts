import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** Ghép class Tailwind, class sau ghi đè class trước khi trùng thuộc tính. */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
