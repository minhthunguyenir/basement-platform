import type { ThrottlerModuleOptions } from '@nestjs/throttler';

/** Số lần thử đăng nhập tối đa cho mỗi tài khoản trong một cửa sổ thời gian. */
export const LOGIN_ATTEMPT_LIMIT = 5;
export const LOGIN_ATTEMPT_WINDOW_MS = 60_000;

/**
 * Đếm theo chuỗi đăng nhập (email/SĐT, không phân biệt hoa thường), không theo IP: API chạy sau
 * load balancer của Render, mà tài liệu Render không nói IP thật nằm ở header nào. Đếm theo IP khi
 * cấu hình proxy sai thì mọi người dùng chung một bộ đếm, hoặc kẻ tấn công giả header để né.
 * Body không có chuỗi đăng nhập hợp lệ thì dùng chung một bộ đếm (request đó sẽ bị Zod trả 400).
 */
export function loginTracker(req: Record<string, unknown>): string {
  const body = req.body as { login?: unknown } | undefined;
  const login = typeof body?.login === 'string' ? body.login.trim().toLowerCase() : '';
  return `login:${login}`;
}

/** Bộ đếm lưu trong bộ nhớ của tiến trình: đủ cho một instance; khởi động lại thì đếm lại từ đầu. */
export const loginThrottlerOptions: ThrottlerModuleOptions = {
  throttlers: [
    { name: 'login', limit: LOGIN_ATTEMPT_LIMIT, ttl: LOGIN_ATTEMPT_WINDOW_MS, getTracker: loginTracker },
  ],
  errorMessage: 'Thử đăng nhập quá nhiều lần, vui lòng thử lại sau 1 phút',
};
