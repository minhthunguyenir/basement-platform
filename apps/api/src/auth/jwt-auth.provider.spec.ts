import type { AuthenticationRegistry, JwtClaims } from '@nestjs/authentication';
import { JwtAuth } from './jwt-auth.provider';
import type { AuthUsersService } from './auth-users.service';
import type { AuthUser } from './auth.types';

const ORG = '00000000-0000-4000-a000-000000000001';
const USER = '00000000-0000-4000-c000-000000000003';

// validate() là protected: gọi qua lớp con để test đúng logic ánh xạ claim -> người dùng.
class TestableJwtAuth extends JwtAuth {
  check(claims: JwtClaims) {
    return this.validate(claims);
  }
}

describe('JwtAuth.validate', () => {
  const user: AuthUser = {
    id: USER,
    organizationId: ORG,
    fullName: 'Nhân viên HCM',
    email: 'staff.hcm@basement.local',
    phone: null,
    memberCode: 'BSM-0003',
  };
  let findActiveUser: jest.Mock;
  let provider: TestableJwtAuth;

  beforeEach(() => {
    findActiveUser = jest.fn().mockResolvedValue(user);
    const registry = { registerProvider: jest.fn() } as unknown as AuthenticationRegistry;
    provider = new TestableJwtAuth({ findActiveUser } as unknown as AuthUsersService, registry);
  });

  it('đọc lại người dùng từ DB theo sub và claim tổ chức', async () => {
    await expect(provider.check({ sub: USER, org: ORG })).resolves.toEqual(user);
    expect(findActiveUser).toHaveBeenCalledWith(ORG, USER);
  });

  it.each([
    ['thiếu sub', { org: ORG }],
    ['thiếu claim tổ chức', { sub: USER }],
    ['claim tổ chức sai kiểu', { sub: USER, org: 123 }],
  ])('%s: từ chối token, không truy vấn DB', (_label, claims) => {
    expect(provider.check(claims as JwtClaims)).toBeNull();
    expect(findActiveUser).not.toHaveBeenCalled();
  });
});
