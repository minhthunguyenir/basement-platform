import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);

  constructor() {
    super({
      log: process.env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
    });
  }

  async onModuleInit() {
    try {
      await this.$connect();
      this.logger.log('Prisma connected to PostgreSQL successfully.');
    } catch (error) {
      this.logger.warn(`Could not connect to PostgreSQL on startup: ${(error as Error).message}`);
    }
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }

  /**
   * Chạy truy vấn với ngữ cảnh Row-Level Security (RLS) của một chi nhánh cụ thể.
   * `SET LOCAL ROLE basement_app` đảm bảo role không phải superuser để RLS bắt buộc có hiệu lực.
   * `SET LOCAL app.current_branch` áp dụng an toàn trong phạm vi transaction hiện tại.
   */
  withBranch<T>(
    branchCode: string,
    callback: (tx: PrismaService) => Promise<T>,
  ): Promise<T> {
    return this.$transaction(async (tx) => {
      // Chuyển sang app role tuân thủ RLS
      await tx.$executeRawUnsafe(`SET LOCAL ROLE basement_app;`);
      // Escape để chống SQL Injection
      const sanitizedBranch = branchCode.replaceAll("'", "''");
      await tx.$executeRawUnsafe(`SET LOCAL app.current_branch = '${sanitizedBranch}';`);
      return callback(tx as unknown as PrismaService);
    });
  }
}
