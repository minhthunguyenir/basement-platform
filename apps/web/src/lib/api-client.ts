import { clearToken, readToken } from "./auth-token";

/** Địa chỉ API. Biến NEXT_PUBLIC_* được gắn cứng lúc build, nên đổi giá trị trên Vercel phải deploy lại. */
export const API_URL = (process.env.NEXT_PUBLIC_API_URL || "http://localhost:3001").replace(/\/+$/, "");

/** Lỗi khi gọi API. status = 0 nghĩa là không kết nối được máy chủ. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

const FALLBACK_MESSAGES: Record<number, string> = {
  400: "Dữ liệu gửi lên không hợp lệ.",
  401: "Phiên đăng nhập không hợp lệ hoặc đã hết hạn, vui lòng đăng nhập lại.",
  403: "Bạn không có quyền thực hiện thao tác này.",
  404: "Không tìm thấy dữ liệu.",
  429: "Bạn thao tác quá nhanh, vui lòng thử lại sau.",
};

interface ApiRequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  /** Gắn access token (mặc định có). Đặt false cho route công khai như đăng nhập. */
  auth?: boolean;
}

/** Lấy thông báo lỗi từ body JSON của NestJS ({ message: string | string[] }). */
async function readErrorMessage(response: Response): Promise<string | undefined> {
  try {
    const body = (await response.json()) as { message?: unknown };
    if (typeof body.message === "string") return body.message;
  } catch {
    // Body không phải JSON.
  }
  return undefined;
}

/** Gọi API, trả về JSON. Gặp 401 khi đang có token thì xóa token để giao diện quay về trang đăng nhập. */
export async function apiFetch<T>(path: string, options: ApiRequestOptions = {}): Promise<T> {
  const { method = "GET", body, auth = true } = options;
  const headers: Record<string, string> = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const token = auth ? readToken() : null;
  if (token) headers.Authorization = `Bearer ${token}`;

  let response: Response;
  try {
    response = await fetch(`${API_URL}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, "Không kết nối được máy chủ Basement. Kiểm tra mạng rồi thử lại.");
  }

  if (!response.ok) {
    if (response.status === 401 && token) clearToken();
    const message = (await readErrorMessage(response)) ?? FALLBACK_MESSAGES[response.status];
    throw new ApiError(response.status, message ?? `Máy chủ trả lỗi ${response.status}.`);
  }
  return (await response.json()) as T;
}
