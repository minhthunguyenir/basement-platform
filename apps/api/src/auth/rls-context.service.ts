import { Injectable } from '@nestjs/common';
import { AuthenticationContext } from '@nestjs/authentication';
import type { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { defaultOrganizationId } from './default-organization';

/**
 * Chạy truy vấn với ngữ cảnh RLS của request hiện tại: tổ chức và người dùng lấy từ token,
 * hoặc tổ chức mặc định và không có người dùng khi chưa đăng nhập. Service nghiệp vụ dùng
 * cái này thay vì tự gọi PrismaService.withContext().
 */
@Injectable()
export class RlsContextService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly authentication: AuthenticationContext,
  ) {}

  run<T>(callback: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    const user = this.authentication.user;
    const context = user
      ? { organizationId: user.organizationId, userId: user.id }
      : { organizationId: defaultOrganizationId() };
    return this.prisma.withContext(context, callback);
  }
}
