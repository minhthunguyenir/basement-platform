import { Injectable } from '@nestjs/common';
import { AuthenticationRegistry, JwtBearerProvider, type JwtClaims } from '@nestjs/authentication';
import { AuthUsersService } from './auth-users.service';
import { ORGANIZATION_CLAIM, type AuthUser } from './auth.types';

/**
 * `Authorization: Bearer <jwt>`: xác minh token do TokenService ký (option `accessToken`),
 * rồi đọc lại người dùng từ DB. Người dùng đã bị xóa mềm thì token bị từ chối (401).
 */
@Injectable()
export class JwtAuth extends JwtBearerProvider<AuthUser> {
  constructor(
    private readonly users: AuthUsersService,
    registry: AuthenticationRegistry,
  ) {
    super();
    registry.registerProvider(this);
  }

  protected validate(claims: JwtClaims): Promise<AuthUser | null> | null {
    const userId = claims.sub;
    const organizationId = claims[ORGANIZATION_CLAIM];
    if (typeof userId !== 'string' || typeof organizationId !== 'string') {
      return null;
    }
    return this.users.findActiveUser(organizationId, userId);
  }
}
