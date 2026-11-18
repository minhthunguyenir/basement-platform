import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';

/** Ngữ cảnh RLS của một giao dịch (xem docs/db/03_rls.sql). */
export interface DbContext {
  /** uuid tổ chức. Thiếu thì mọi bảng trả 0 dòng (RLS đóng mặc định). */
  organizationId: string;
  /** uuid người dùng đã đăng nhập; bỏ trống khi chưa đăng nhập. */
  userId?: string | null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);

  constructor() {
    super({
      log: process.env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
      // basement_app không có quyền SELECT users.password_hash: bỏ cột này khỏi mọi truy vấn.
      // Lấy hash để đăng nhập qua hàm app.login_lookup(). Lưu ý: type bên trong $transaction
      // vẫn hiện password_hash (giới hạn của Prisma 6), nhưng lúc chạy cột không được select.
      omit: { users: { password_hash: true } },
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
   * Chạy truy vấn trong một giao dịch có ngữ cảnh RLS: gán app.organization_id và app.user_id
   * bằng set_config(..., true) nên giá trị chỉ sống trong giao dịch này (an toàn với connection pool).
   * Chi nhánh nào được xem do DB tự quyết định qua user_roles, không lấy từ client.
   * Ứng dụng phải kết nối bằng role basement_app (DATABASE_URL); superuser sẽ bỏ qua RLS.
   */
  withContext<T>(context: DbContext, callback: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    const { organizationId, userId } = context;
    if (!UUID_RE.test(organizationId)) {
      throw new Error('withContext: organizationId phải là uuid hợp lệ');
    }
    if (userId && !UUID_RE.test(userId)) {
      throw new Error('withContext: userId phải là uuid hợp lệ');
    }
    return this.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT set_config('app.organization_id', ${organizationId}, true),
                                set_config('app.user_id', ${userId ?? ''}, true)`;
      return callback(tx);
    });
  }
}
