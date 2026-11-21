import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/** Số bảng nghiệp vụ trong docs/db/01_schema.sql; tất cả phải bật và ép RLS. */
const EXPECTED_TABLES = 25;

export interface OccupancyRow {
  branch_id: string;
  branch_name: string;
  capacity: number;
  active_sessions: number;
  free_seats: number;
}

@Injectable()
export class HealthService {
  private readonly logger = new Logger(HealthService.name);

  constructor(private readonly prisma: PrismaService) {}

  getHealth() {
    return {
      status: 'ok',
      service: '@basement/api',
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Kiểm tra cấu hình Row-Level Security đang chạy (chỉ đọc, không ghi dữ liệu):
   * - ứng dụng kết nối bằng role basement_app, không phải superuser;
   * - đủ 25 bảng bật ENABLE + FORCE ROW LEVEL SECURITY;
   * - không gán ngữ cảnh tổ chức thì không đọc được dòng nào (đóng mặc định);
   * - nếu có DEFAULT_ORGANIZATION_ID: số chỗ trống từng chi nhánh qua app.branch_occupancy().
   * Bộ kiểm thử phân quyền đầy đủ là docs/db/04_rls_tests.sql (chạy trong CI).
   */
  async rlsTest() {
    try {
      const [identity] = await this.prisma.$queryRaw<Array<{ role: string; is_superuser: string }>>`
        SELECT current_user AS role, current_setting('is_superuser') AS is_superuser`;

      const extension = await this.prisma.$queryRaw<Array<{ extversion: string }>>`
        SELECT extversion FROM pg_extension WHERE extname = 'vector'`;

      const [rls] = await this.prisma.$queryRaw<Array<{ tables: number; forced: number }>>`
        SELECT count(*)::int AS tables,
               count(*) FILTER (WHERE c.relrowsecurity AND c.relforcerowsecurity)::int AS forced
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname <> '_prisma_migrations'`;

      // Ngoài withContext(): app.organization_id chưa gán nên policy phải chặn hết.
      const [withoutContext] = await this.prisma.$queryRaw<Array<{ rows: number }>>`
        SELECT count(*)::int AS rows FROM branches`;

      const organizationId = process.env.DEFAULT_ORGANIZATION_ID;
      const occupancy = organizationId
        ? await this.prisma.withContext({ organizationId }, (tx) =>
            tx.$queryRaw<OccupancyRow[]>`SELECT * FROM app.branch_occupancy()`,
          )
        : null;

      const checks = {
        connectedAsAppRole: identity.role === 'basement_app' && identity.is_superuser === 'off',
        allTablesForceRls: rls.tables === EXPECTED_TABLES && rls.forced === EXPECTED_TABLES,
        closedWithoutContext: withoutContext.rows === 0,
      };
      const success = Object.values(checks).every(Boolean);

      return {
        status: 'ok',
        database: 'connected',
        connectedAs: { role: identity.role, superuser: identity.is_superuser === 'on' },
        pgvector: extension.length > 0 ? { installed: true, version: extension[0].extversion } : { installed: false },
        rlsVerification: {
          success,
          checks,
          tables: { expected: EXPECTED_TABLES, found: rls.tables, forceRls: rls.forced },
          rowsVisibleWithoutContext: withoutContext.rows,
          summary: success
            ? 'RLS hoạt động: ứng dụng chạy bằng basement_app, 25/25 bảng ép RLS, không có ngữ cảnh tổ chức thì không đọc được dữ liệu.'
            : 'Cảnh báo: cấu hình RLS chưa đúng. Kiểm tra DATABASE_URL (phải là basement_app) và migration.',
        },
        occupancy: occupancy ?? 'Chưa cấu hình DEFAULT_ORGANIZATION_ID',
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.logger.error(`RLS check failed: ${message}`);
      return { status: 'error', database: 'error', message };
    }
  }
}
