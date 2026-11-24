import { Injectable } from '@nestjs/common';
import { isUuid } from '../common/uuid';
import { PrismaService } from '../prisma/prisma.service';
import type { AuthUser, AuthUserRole } from './auth.types';

/** Đọc người dùng và vai trò của chính họ, dưới RLS (policy *_select_self). */
@Injectable()
export class AuthUsersService {
  constructor(private readonly prisma: PrismaService) {}

  /** Người dùng còn hoạt động (chưa xóa mềm, không phải khách vãng lai), hoặc `null`. */
  async findActiveUser(organizationId: string, userId: string): Promise<AuthUser | null> {
    if (!isUuid(organizationId) || !isUuid(userId)) {
      return null;
    }
    const user = await this.prisma.withContext({ organizationId, userId }, (tx) =>
      tx.users.findFirst({
        where: { id: userId, organization_id: organizationId, deleted_at: null, is_guest: false },
        select: { id: true, organization_id: true, full_name: true, email: true, phone: true, member_code: true },
      }),
    );
    if (!user) {
      return null;
    }
    return {
      id: user.id,
      organizationId: user.organization_id,
      fullName: user.full_name,
      email: user.email,
      phone: user.phone,
      memberCode: user.member_code,
    };
  }

  /** Các vai trò còn hiệu lực của người dùng. */
  async findRoles(user: AuthUser): Promise<AuthUserRole[]> {
    const rows = await this.prisma.withContext({ organizationId: user.organizationId, userId: user.id }, (tx) =>
      tx.user_roles.findMany({
        where: { user_id: user.id, deleted_at: null },
        select: { role: true, branches: { select: { id: true, code: true, name: true } } },
        orderBy: [{ role: 'asc' }, { branch_id: 'asc' }],
      }),
    );
    return rows.map((row) => ({ role: row.role, branch: row.branches }));
  }
}
