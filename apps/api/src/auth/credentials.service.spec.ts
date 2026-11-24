import { PasswordHasher } from '@nestjs/authentication';
import { CredentialsService } from './credentials.service';
import type { PrismaService } from '../prisma/prisma.service';

const ORG = '00000000-0000-4000-a000-000000000001';
const USER = '00000000-0000-4000-c000-000000000003';

describe('CredentialsService.verify', () => {
  // Chi phí scrypt thấp cho test nhanh; định dạng hash giống hệt bản thật.
  const hasher = new PasswordHasher({ logN: 10 });
  let rows: Array<{ user_id: string; password_hash: string | null }>;
  let queryRaw: jest.Mock;
  let withContext: jest.Mock;
  let service: CredentialsService;

  beforeEach(() => {
    process.env.DEFAULT_ORGANIZATION_ID = ORG;
    rows = [];
    queryRaw = jest.fn(() => Promise.resolve(rows));
    withContext = jest.fn((_ctx: unknown, cb: (tx: unknown) => unknown) => cb({ $queryRaw: queryRaw }));
    service = new CredentialsService({ withContext } as unknown as PrismaService, hasher);
  });

  it('đúng mật khẩu: trả về người dùng và tổ chức, tra cứu qua app.login_lookup() với ngữ cảnh tổ chức', async () => {
    rows = [{ user_id: USER, password_hash: await hasher.hash('Mat-khau-dung-123') }];

    await expect(service.verify('staff.hcm@basement.local', 'Mat-khau-dung-123')).resolves.toEqual({
      userId: USER,
      organizationId: ORG,
    });
    expect(withContext).toHaveBeenCalledWith({ organizationId: ORG }, expect.any(Function));
    const [strings, login] = queryRaw.mock.calls[0] as [TemplateStringsArray, string];
    expect(strings.join('?')).toContain('FROM app.login_lookup(?)');
    expect(login).toBe('staff.hcm@basement.local');
  });

  it('sai mật khẩu: null', async () => {
    rows = [{ user_id: USER, password_hash: await hasher.hash('Mat-khau-dung-123') }];
    await expect(service.verify('staff.hcm@basement.local', 'sai')).resolves.toBeNull();
  });

  it('không có tài khoản: null', async () => {
    await expect(service.verify('khong-ton-tai@basement.local', 'bat-ky')).resolves.toBeNull();
  });

  it('mật khẩu placeholder của seed (không phải hash scrypt): null, kể cả khi nhập đúng chuỗi placeholder', async () => {
    rows = [{ user_id: USER, password_hash: '!seed-chua-dat-mat-khau' }];
    await expect(service.verify('staff.hcm@basement.local', '!seed-chua-dat-mat-khau')).resolves.toBeNull();
  });

  it('chuỗi đăng nhập khớp nhiều người (email người này, số điện thoại người kia): null', async () => {
    const hash = await hasher.hash('Mat-khau-dung-123');
    rows = [
      { user_id: USER, password_hash: hash },
      { user_id: '00000000-0000-4000-c000-000000000011', password_hash: hash },
    ];
    await expect(service.verify('0900000011', 'Mat-khau-dung-123')).resolves.toBeNull();
  });

  it('thiếu DEFAULT_ORGANIZATION_ID: báo lỗi cấu hình, không truy vấn DB', async () => {
    delete process.env.DEFAULT_ORGANIZATION_ID;
    await expect(service.verify('a', 'b')).rejects.toThrow('DEFAULT_ORGANIZATION_ID');
    expect(withContext).not.toHaveBeenCalled();
  });
});
