import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class HealthService {
  constructor(private readonly prisma: PrismaService) {}

  getHealth() {
    return {
      status: 'ok',
      service: '@basement/api',
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Kiểm thử kết nối PostgreSQL, pgvector và tính cô lập dữ liệu theo chi nhánh (Row-Level Security - RLS).
   * Tự động seed 3 bản ghi mẫu nếu bảng đang trống và kiểm tra tính toàn vẹn của chính sách RLS.
   */
  async rlsTest(specificBranch?: string) {
    try {
      // 1. Kiểm tra kết nối và pgvector extension
      const extensionCheck = await this.prisma.$queryRawUnsafe<Array<{ extname: string; extversion: string }>>(
        `SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';`,
      );
      const hasPgVector = extensionCheck.length > 0;

      // 2. Tự động chèn 3 bản ghi mẫu (HCM, DAD, VCA) nếu bảng đang trống hoặc chưa có dữ liệu chi nhánh
      const sampleBranches = [
        { code: 'HCM', title: 'Hồ sơ dự án Tòa nhà Bitexco (Chi nhánh TP.HCM)' },
        { code: 'DAD', title: 'Hồ sơ dự án Cầu Rồng (Chi nhánh Đà Nẵng)' },
        { code: 'VCA', title: 'Hồ sơ dự án Cầu Cần Thơ (Chi nhánh Cần Thơ)' },
      ];

      for (const sample of sampleBranches) {
        await this.prisma.withBranch(sample.code, async (tx) => {
          // Query kiểm tra bản ghi theo chi nhánh
          const existing = await tx.$queryRawUnsafe<Array<{ id: string }>>(
            `SELECT id FROM "branch_samples" WHERE "branch_code" = $1 LIMIT 1;`,
            sample.code,
          );
          if (existing.length === 0) {
            await tx.$queryRawUnsafe(
              `INSERT INTO "branch_samples" ("id", "branch_code", "title", "created_at")
               VALUES (gen_random_uuid(), $1, $2, NOW());`,
              sample.code,
              sample.title,
            );
          }
        });
      }

      // 3. Nếu người dùng chỉ định query ?branch=...
      if (specificBranch) {
        const records = await this.prisma.withBranch(specificBranch, (tx) => {
          return tx.$queryRawUnsafe<Array<{ id: string; branch_code: string; title: string; created_at: Date }>>(
            `SELECT id, branch_code, title, created_at FROM "branch_samples";`,
          );
        });

        return {
          status: 'ok',
          database: 'connected',
          pgvector: hasPgVector ? { installed: true, version: extensionCheck[0].extversion } : { installed: false },
          queryBranch: specificBranch,
          recordsFound: records.length,
          records,
        };
      }

      // 4. Kiểm tra cô lập dữ liệu tự động giữa 3 chi nhánh: HCM, DAD, VCA
      const [hcmRecords, dadRecords, vcaRecords, unauthorizedRecords] = await Promise.all([
        this.prisma.withBranch('HCM', (tx) => {
          return tx.$queryRawUnsafe<Array<{ id: string; branch_code: string; title: string }>>(
            `SELECT id, branch_code, title FROM "branch_samples";`,
          );
        }),
        this.prisma.withBranch('DAD', (tx) => {
          return tx.$queryRawUnsafe<Array<{ id: string; branch_code: string; title: string }>>(
            `SELECT id, branch_code, title FROM "branch_samples";`,
          );
        }),
        this.prisma.withBranch('VCA', (tx) => {
          return tx.$queryRawUnsafe<Array<{ id: string; branch_code: string; title: string }>>(
            `SELECT id, branch_code, title FROM "branch_samples";`,
          );
        }),
        // Query dưới role basement_app nhưng KHÔNG set app.current_branch
        this.prisma.$transaction(async (tx) => {
          await tx.$executeRawUnsafe(`SET LOCAL ROLE basement_app;`);
          return tx.$queryRawUnsafe<Array<{ id: string }>>(`SELECT id FROM "branch_samples";`);
        }),
      ]);

      // Kiểm tra tính toàn vẹn RLS
      const isHcmIsolated = hcmRecords.every((r) => r.branch_code === 'HCM') && hcmRecords.length > 0;
      const isDadIsolated = dadRecords.every((r) => r.branch_code === 'DAD') && dadRecords.length > 0;
      const isVcaIsolated = vcaRecords.every((r) => r.branch_code === 'VCA') && vcaRecords.length > 0;
      const isUnauthorizedBlocked = unauthorizedRecords.length === 0;

      const isRlsSuccessful = isHcmIsolated && isDadIsolated && isVcaIsolated && isUnauthorizedBlocked;

      return {
        status: 'ok',
        database: 'connected',
        pgvector: hasPgVector
          ? { status: 'active', version: extensionCheck[0].extversion }
          : { status: 'missing' },
        rlsVerification: {
          success: isRlsSuccessful,
          rulesChecked: [
            'ENABLE ROW LEVEL SECURITY',
            'FORCE ROW LEVEL SECURITY',
            'POLICY USING ("branch_code" = current_setting(\'app.current_branch\', true))',
            'SET LOCAL ROLE basement_app',
          ],
          tests: {
            HCM: {
              queriedAs: 'HCM',
              count: hcmRecords.length,
              records: hcmRecords,
              isolatedOnlyToHCM: isHcmIsolated,
            },
            DAD: {
              queriedAs: 'DAD',
              count: dadRecords.length,
              records: dadRecords,
              isolatedOnlyToDAD: isDadIsolated,
            },
            VCA: {
              queriedAs: 'VCA',
              count: vcaRecords.length,
              records: vcaRecords,
              isolatedOnlyToVCA: isVcaIsolated,
            },
            withoutBranchContext: {
              queriedAs: 'none (no app.current_branch set)',
              count: unauthorizedRecords.length,
              blocked: isUnauthorizedBlocked,
            },
          },
          summary: isRlsSuccessful
            ? 'RLS (Row-Level Security) hoạt động chính xác: Mỗi chi nhánh (HCM, DAD, VCA) chỉ truy xuất được đúng dữ liệu của mình. Mọi truy vấn không có ngữ cảnh chi nhánh đều bị chặn hoàn toàn.'
            : 'Cảnh báo: Kiểm tra RLS phát hiện bất thường trong việc lọc dữ liệu chi nhánh.',
        },
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error('[HealthService] RLS test failed:', error);
      return {
        status: 'error',
        database: 'error',
        message: errorMessage,
        error: errorMessage,
      };
    }
  }

  async testRowLevelSecurity(specificBranch?: string) {
    return this.rlsTest(specificBranch);
  }
}
