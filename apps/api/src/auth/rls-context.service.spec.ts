import type { AuthenticationContext } from '@nestjs/authentication';
import { RlsContextService } from './rls-context.service';
import type { PrismaService } from '../prisma/prisma.service';
import type { AuthUser } from './auth.types';

const DEFAULT_ORG = '00000000-0000-4000-a000-000000000001';
const USER_ORG = '00000000-0000-4000-a000-000000000002';
const USER = '00000000-0000-4000-c000-000000000003';

describe('RlsContextService.run', () => {
  let withContext: jest.Mock;
  let current: AuthUser | null;
  let service: RlsContextService;

  beforeEach(() => {
    process.env.DEFAULT_ORGANIZATION_ID = DEFAULT_ORG;
    withContext = jest.fn((_ctx: unknown, cb: (tx: unknown) => unknown) => cb('tx'));
    current = null;
    const authentication = {
      get user() {
        return current;
      },
    } as unknown as AuthenticationContext;
    service = new RlsContextService({ withContext } as unknown as PrismaService, authentication);
  });

  it('đã đăng nhập: dùng tổ chức và id của người dùng trong token, không dùng tổ chức mặc định', async () => {
    current = { id: USER, organizationId: USER_ORG, fullName: null, email: null, phone: null, memberCode: 'X' };

    await expect(service.run((tx) => Promise.resolve(tx))).resolves.toBe('tx');
    expect(withContext).toHaveBeenCalledWith({ organizationId: USER_ORG, userId: USER }, expect.any(Function));
  });

  it('chưa đăng nhập: tổ chức mặc định, không có người dùng', async () => {
    await service.run(() => Promise.resolve(null));
    expect(withContext).toHaveBeenCalledWith({ organizationId: DEFAULT_ORG }, expect.any(Function));
  });
});
