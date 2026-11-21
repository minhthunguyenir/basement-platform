import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { HealthService } from './health.service';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(private readonly healthService: HealthService) {}

  @Get()
  @ApiOperation({ summary: 'Kiểm tra trạng thái hoạt động của dịch vụ API' })
  @ApiResponse({
    status: 200,
    description: 'Dịch vụ API đang hoạt động bình thường',
    schema: {
      type: 'object',
      properties: {
        status: { type: 'string', example: 'ok' },
        service: { type: 'string', example: '@basement/api' },
        timestamp: { type: 'string', example: '2026-11-13T04:30:00.000Z' },
      },
    },
  })
  getHealth() {
    return this.healthService.getHealth();
  }

  @Get('rls-test')
  @ApiOperation({
    summary: 'Kiểm tra kết nối PostgreSQL, pgvector và cấu hình Row-Level Security (RLS)',
    description:
      'Chỉ đọc. Xác nhận ứng dụng kết nối bằng role basement_app (không phải superuser), 25/25 bảng bật FORCE ROW LEVEL SECURITY, ' +
      'và khi chưa gán ngữ cảnh tổ chức thì không đọc được dòng nào. Bộ kiểm thử phân quyền đầy đủ: docs/db/04_rls_tests.sql.',
  })
  @ApiResponse({
    status: 200,
    description: 'Kết quả kiểm tra kết nối cơ sở dữ liệu và cấu hình Row-Level Security',
  })
  testRowLevelSecurity() {
    return this.healthService.rlsTest();
  }
}
