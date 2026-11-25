import { useSyncExternalStore } from "react";

/**
 * Lưu access token ở localStorage của trình duyệt. Web (Vercel) và API (Render) khác tên miền nên
 * không dùng được cookie của API một cách đơn giản. Đổi lại: nếu trang bị chèn script (XSS) thì
 * token có thể bị đọc. Token tự hết hạn sau 12 giờ và API không có refresh token.
 */
const STORAGE_KEY = "basement.auth";

interface StoredToken {
  accessToken: string;
  /** Thời điểm hết hạn, ms kể từ epoch. */
  expiresAt: number;
}

const listeners = new Set<() => void>();

function notify() {
  listeners.forEach((listener) => listener());
}

function readRaw(): string | null {
  try {
    return window.localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

function parse(raw: string | null): string | null {
  if (!raw) return null;
  try {
    const stored = JSON.parse(raw) as Partial<StoredToken>;
    if (typeof stored.accessToken !== "string" || typeof stored.expiresAt !== "number") return null;
    return stored.expiresAt > Date.now() ? stored.accessToken : null;
  } catch {
    return null;
  }
}

/** Token còn hạn, hoặc null. Chỉ gọi ở trình duyệt. */
export function readToken(): string | null {
  return parse(readRaw());
}

export function saveToken(accessToken: string, expiresInSeconds: number) {
  const stored: StoredToken = { accessToken, expiresAt: Date.now() + expiresInSeconds * 1000 };
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
  } catch {
    // Trình duyệt chặn lưu trữ (chế độ riêng tư...): vẫn chạy được, chỉ là tải lại trang phải đăng nhập lại.
  }
  notify();
}

export function clearToken() {
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Bỏ qua: không có gì để xóa.
  }
  notify();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  // Đăng nhập/đăng xuất ở tab khác cũng cập nhật tab này.
  const onStorage = (event: StorageEvent) => {
    if (event.key === STORAGE_KEY) listener();
  };
  window.addEventListener("storage", onStorage);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", onStorage);
  };
}

/** Token hiện tại; khi render ở server luôn là null. */
export function useAuthToken(): string | null {
  const raw = useSyncExternalStore(subscribe, readRaw, () => null);
  return parse(raw);
}
