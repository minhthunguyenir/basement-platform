/** Người dùng đã đăng nhập, đọc lại từ DB ở mỗi request (không lấy từ token). */
export interface AuthUser {
  id: string;
  organizationId: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
  memberCode: string;
}

/** Vai trò của người dùng: toàn chuỗi (`branch` = null) hoặc tại một chi nhánh. */
export interface AuthUserRole {
  role: 'owner' | 'branch_manager' | 'staff' | 'customer';
  branch: { id: string; code: string; name: string } | null;
}

/** Claim riêng của Basement trong access token: tổ chức của người dùng (không đổi theo thời gian). */
export const ORGANIZATION_CLAIM = 'org';

// Kiểu cho @CurrentUser(), AuthenticationContext.user, và TokenService.issue() khi tắt refresh token.
declare module '@nestjs/authentication' {
  interface AuthenticationTypes {
    user: AuthUser;
    refreshTokens: false;
  }
}
