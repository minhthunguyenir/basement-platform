import { Body, Controller, Get, HttpCode, Post, UseGuards } from '@nestjs/common';
import { AuthenticationError, CurrentUser, Public, TokenService } from '@nestjs/authentication';
import { ThrottlerGuard } from '@nestjs/throttler';
import { ApiBearerAuth, ApiBody, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { z } from 'zod';
import { AuthUsersService } from './auth-users.service';
import { CredentialsService } from './credentials.service';
import { ORGANIZATION_CLAIM, type AuthUser } from './auth.types';

export const loginSchema = z.object({
  /** Email hoặc số điện thoại. */
  login: z.string().trim().min(1).max(255),
  password: z.string().min(1).max(1024),
});
export type LoginDto = z.infer<typeof loginSchema>;

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly credentials: CredentialsService,
    private readonly tokens: TokenService,
    private readonly users: AuthUsersService,
  ) {}

  @Public()
  @Post('login')
  @HttpCode(200)
  @UseGuards(ThrottlerGuard)
  @ApiOperation({ summary: 'Đăng nhập bằng email hoặc số điện thoại, nhận access token (Bearer, hiệu lực 12 giờ)' })
  @ApiBody({
    schema: {
      type: 'object',
      required: ['login', 'password'],
      properties: {
        login: { type: 'string', example: 'staff.hcm@basement.local', description: 'Email hoặc số điện thoại' },
        password: { type: 'string', example: '••••••••' },
      },
    },
  })
  @ApiResponse({
    status: 200,
    description: 'Đăng nhập thành công',
    schema: {
      type: 'object',
      properties: {
        accessToken: { type: 'string' },
        tokenType: { type: 'string', example: 'Bearer' },
        expiresIn: { type: 'number', example: 43200, description: 'Số giây đến khi token hết hạn' },
      },
    },
  })
  @ApiResponse({ status: 401, description: 'Sai email/số điện thoại hoặc mật khẩu' })
  @ApiResponse({ status: 429, description: 'Quá 5 lần thử trong 1 phút cho cùng một tài khoản' })
  async login(@Body({ schema: loginSchema }) body: LoginDto) {
    const verified = await this.credentials.verify(body.login, body.password);
    if (!verified) {
      throw new AuthenticationError('Sai email/số điện thoại hoặc mật khẩu', { code: 'invalid_credentials' });
    }
    const { accessToken, expiresIn } = await this.tokens.issue(verified.userId, {
      method: 'password',
      claims: { [ORGANIZATION_CLAIM]: verified.organizationId },
    });
    return { accessToken, tokenType: 'Bearer', expiresIn };
  }

  @Get('me')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Thông tin người dùng đang đăng nhập và các vai trò của họ' })
  @ApiResponse({ status: 401, description: 'Thiếu, sai hoặc hết hạn token' })
  async me(@CurrentUser() user: AuthUser) {
    return { ...user, roles: await this.users.findRoles(user) };
  }
}
