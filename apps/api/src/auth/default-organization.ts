import { isUuid } from '../common/uuid';

/**
 * Tổ chức dùng khi chưa biết người dùng (đăng nhập, khách chưa đăng nhập).
 * Hệ thống hiện vận hành một tổ chức; giao diện thêm tổ chức nằm ngoài phạm vi.
 */
export function defaultOrganizationId(): string {
  const id = process.env.DEFAULT_ORGANIZATION_ID;
  if (!isUuid(id)) {
    throw new Error('DEFAULT_ORGANIZATION_ID chưa được cấu hình hoặc không phải uuid');
  }
  return id;
}
