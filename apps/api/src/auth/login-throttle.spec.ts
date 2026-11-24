import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  INestApplication,
  StandardSchemaValidationPipe,
} from '@nestjs/common';
import type { Response } from 'express';
import { Test } from '@nestjs/testing';
import { AuthenticationError, TokenService } from '@nestjs/authentication';
import { ThrottlerModule } from '@nestjs/throttler';
import request from 'supertest';
import type { App } from 'supertest/types';
import { AuthController } from './auth.controller';
import { AuthUsersService } from './auth-users.service';
import { CredentialsService } from './credentials.service';
import { LOGIN_ATTEMPT_LIMIT, loginThrottlerOptions, loginTracker } from './login-throttle';

describe('loginTracker', () => {
  it('cùng tài khoản dù khác hoa thường/khoảng trắng: chung một bộ đếm', () => {
    expect(loginTracker({ body: { login: '  Staff.HCM@basement.local ' } })).toBe(
      loginTracker({ body: { login: 'staff.hcm@basement.local' } }),
    );
  });

  it('không phụ thuộc IP hay header X-Forwarded-For', () => {
    const a = loginTracker({ ip: '1.1.1.1', headers: { 'x-forwarded-for': '9.9.9.9' }, body: { login: 'x' } });
    const b = loginTracker({ ip: '2.2.2.2', body: { login: 'x' } });
    expect(a).toBe(b);
  });
});

/** Trong app thật, AuthenticationModule đổi AuthenticationError thành 401; test này không nạp module đó. */
@Catch(AuthenticationError)
class AuthenticationErrorTo401 implements ExceptionFilter {
  catch(_error: AuthenticationError, host: ArgumentsHost) {
    host.switchToHttp().getResponse<Response>().status(401).end();
  }
}

describe('POST /auth/login: giới hạn số lần thử', () => {
  let app: INestApplication<App>;
  let verify: jest.Mock;

  beforeEach(async () => {
    verify = jest.fn().mockResolvedValue(null); // luôn sai mật khẩu
    const moduleRef = await Test.createTestingModule({
      imports: [ThrottlerModule.forRoot(loginThrottlerOptions)],
      controllers: [AuthController],
      providers: [
        { provide: CredentialsService, useValue: { verify } },
        { provide: TokenService, useValue: {} },
        { provide: AuthUsersService, useValue: {} },
      ],
    }).compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(new StandardSchemaValidationPipe());
    app.useGlobalFilters(new AuthenticationErrorTo401());
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  const attempt = (login: string) =>
    request(app.getHttpServer()).post('/auth/login').send({ login, password: 'sai-mat-khau' });

  it(`quá ${LOGIN_ATTEMPT_LIMIT} lần/phút cho một tài khoản: 429 và không kiểm tra mật khẩu nữa`, async () => {
    for (let i = 0; i < LOGIN_ATTEMPT_LIMIT; i++) {
      await attempt('staff.hcm@basement.local').expect(401);
    }
    const blocked = await attempt('STAFF.HCM@basement.local').expect(429);
    expect(blocked.headers['retry-after-login']).toBeDefined();
    expect(verify).toHaveBeenCalledTimes(LOGIN_ATTEMPT_LIMIT);

    // Tài khoản khác không bị ảnh hưởng.
    await attempt('owner@basement.local').expect(401);
  });
});
