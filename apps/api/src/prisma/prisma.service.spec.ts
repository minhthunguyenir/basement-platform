import { PrismaService } from './prisma.service';

// Unit test không kết nối DB: giả lập $transaction để kiểm tra ngữ cảnh RLS được gán đúng.
// Hành vi RLS thật được kiểm bằng docs/db/04_rls_tests.sql (job CI db-rls).
const ORG = '11111111-1111-1111-1111-111111111111';
const USER = '33333333-3333-3333-3333-333333333301';

describe('PrismaService.withContext', () => {
  let service: PrismaService;
  let tx: { $queryRaw: jest.Mock };

  beforeEach(() => {
    process.env.DATABASE_URL ??= 'postgresql://basement_app:x@localhost:5432/test';
    service = new PrismaService();
    tx = { $queryRaw: jest.fn().mockResolvedValue([]) };
    jest.spyOn(service, '$transaction').mockImplementation(((fn: (t: unknown) => unknown) => Promise.resolve(fn(tx))) as any);
  });

  it('gán app.organization_id và app.user_id bằng tham số trước khi chạy callback', async () => {
    const callback = jest.fn().mockResolvedValue('ok');

    await expect(service.withContext({ organizationId: ORG, userId: USER }, callback)).resolves.toBe('ok');

    const [strings, ...values] = tx.$queryRaw.mock.calls[0] as [TemplateStringsArray, ...unknown[]];
    expect(strings.join('?').replace(/\s+/g, ' ')).toContain(
      "set_config('app.organization_id', ?, true), set_config('app.user_id', ?, true)",
    );
    expect(values).toEqual([ORG, USER]);
    expect(callback).toHaveBeenCalledWith(tx);
    expect(tx.$queryRaw.mock.invocationCallOrder[0]).toBeLessThan(callback.mock.invocationCallOrder[0]);
  });

  it('dùng chuỗi rỗng cho app.user_id khi chưa đăng nhập', async () => {
    await service.withContext({ organizationId: ORG }, () => Promise.resolve(null));

    const [, ...values] = tx.$queryRaw.mock.calls[0] as [TemplateStringsArray, ...unknown[]];
    expect(values).toEqual([ORG, '']);
  });

  it.each([["x' OR 1=1 --"], [''], ['not-a-uuid']])('từ chối organizationId không phải uuid: %p', (organizationId) => {
    expect(() => service.withContext({ organizationId }, () => Promise.resolve(null))).toThrow('organizationId');
    expect(tx.$queryRaw).not.toHaveBeenCalled();
  });

  it('từ chối userId không phải uuid', () => {
    expect(() => service.withContext({ organizationId: ORG, userId: 'abc' }, () => Promise.resolve(null))).toThrow(
      'userId',
    );
  });
});
