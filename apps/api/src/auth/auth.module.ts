import { Module } from '@nestjs/common';
import { AuthenticationModule } from '@nestjs/authentication';
import { ThrottlerModule } from '@nestjs/throttler';
import { AuthController } from './auth.controller';
import { AuthUsersService } from './auth-users.service';
import { CredentialsService } from './credentials.service';
import { JwtAuth } from './jwt-auth.provider';
import { loginThrottlerOptions } from './login-throttle';
import { RlsContextService } from './rls-context.service';
import './auth.types';

/** Độ dài tối thiểu của khóa HS256 mà @nestjs/authentication chấp nhận. */
const MIN_SECRET_BYTES = 32;

function accessTokenSecret(): string {
  const secret = process.env.AUTH_JWT_SECRET;
  if (!secret || Buffer.byteLength(secret) < MIN_SECRET_BYTES) {
    throw new Error(
      `AUTH_JWT_SECRET chưa được cấu hình hoặc ngắn hơn ${MIN_SECRET_BYTES} byte (tạo bằng: openssl rand -base64 32)`,
    );
  }
  return secret;
}

/**
 * Đăng nhập bằng mật khẩu, cấp access token JWT (HS256, 12 giờ, không có refresh token: hết hạn thì
 * đăng nhập lại; không cần bảng hay Redis để lưu). Guard toàn cục: mọi route cần token, trừ @Public().
 * POST /auth/login bị giới hạn số lần thử cho mỗi tài khoản (xem login-throttle.ts).
 */
@Module({
  imports: [
    AuthenticationModule.forRootAsync({
      useFactory: () => ({
        accessToken: {
          key: accessTokenSecret(),
          issuer: 'basement-api',
          audience: 'basement-web',
          ttl: '12h',
        },
        refreshToken: false,
      }),
    }),
    ThrottlerModule.forRoot(loginThrottlerOptions),
  ],
  controllers: [AuthController],
  providers: [JwtAuth, CredentialsService, AuthUsersService, RlsContextService],
  exports: [AuthUsersService, RlsContextService],
})
export class AuthModule {}
