import { Controller, Get, Query } from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiResponse, ApiTags } from '@nestjs/swagger';
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
    summary: 'Kiểm thử kết nối PostgreSQL, pgvector và tính cô lập dữ liệu theo chi nhánh (Row-Level Security - RLS)',
    description:
      'Tự động kiểm tra tính cô lập dữ liệu giữa 3 chi nhánh (HCM, DAD, VCA) hoặc truy vấn dữ liệu của một chi nhánh cụ thể thông qua policy Row-Level Security.',
  })
  @ApiQuery({
    name: 'branch',
    required: false,
    description: 'Mã chi nhánh cần kiểm tra dữ liệu (ví dụ: HCM, DAD, VCA)',
    example: 'HCM',
  })
  @ApiResponse({
    status: 200,
    description: 'Kết quả kiểm tra kết nối cơ sở dữ liệu và tính toàn vẹn của chính sách Row-Level Security',
  })
  testRowLevelSecurity(@Query('branch') specificBranch?: string) {
    return this.healthService.rlsTest(specificBranch);
  }
}
