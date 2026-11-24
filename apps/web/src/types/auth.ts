// Khớp với DTO của apps/api/src/auth (auth.controller.ts, auth.types.ts).

export interface LoginRequest {
  /** Email hoặc số điện thoại. */
  login: string;
  password: string;
}

export interface LoginResponse {
  accessToken: string;
  tokenType: "Bearer";
  /** Số giây đến khi token hết hạn. */
  expiresIn: number;
}

export type UserRoleName = "owner" | "branch_manager" | "staff" | "customer";

export interface UserRole {
  role: UserRoleName;
  /** null = vai trò áp dụng cho toàn chuỗi. */
  branch: { id: string; code: string; name: string } | null;
}

export interface CurrentUser {
  id: string;
  organizationId: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
  memberCode: string;
  roles: UserRole[];
}
