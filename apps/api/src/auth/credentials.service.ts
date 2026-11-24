import { Injectable } from '@nestjs/common';
import { PasswordHasher } from '@nestjs/authentication';
import { ConcurrencyLimit } from '../common/concurrency-limit';
import { PrismaService } from '../prisma/prisma.service';
import { defaultOrganizationId } from './default-organization';

export interface VerifiedCredentials {
  userId: string;
  organizationId: string;
}

interface LoginLookupRow {
  user_id: string;
  password_hash: string | null;
}

/** Hash do PasswordHasher tạo ra; giá trị khác (vd. placeholder của seed) coi như chưa có mật khẩu. */
const SCRYPT_HASH_PREFIX = '$scrypt$';

/**
 * Mỗi lần kiểm tra scrypt (logN 17) dùng ~128 MiB. Render Free chỉ có 512 MB, nên chỉ cho 2 lần
 * chạy cùng lúc (~256 MiB); các lần khác xếp hàng chờ thay vì làm tiến trình hết bộ nhớ.
 */
export const MAX_CONCURRENT_PASSWORD_CHECKS = 2;

/** Kiểm tra email/số điện thoại + mật khẩu. */
@Injectable()
export class CredentialsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly passwordHasher: PasswordHasher,
  ) {}

  private readonly passwordChecks = new ConcurrencyLimit(MAX_CONCURRENT_PASSWORD_CHECKS);

  /**
   * Trả về người dùng khi đúng, `null` khi sai. Sai email và sai mật khẩu mất thời gian như nhau
   * (PasswordHasher kiểm một hash giả), nên không lộ tài khoản nào tồn tại.
   * basement_app không được đọc users.password_hash: lấy qua hàm SECURITY DEFINER app.login_lookup().
   */
  async verify(login: string, password: string): Promise<VerifiedCredentials | null> {
    const organizationId = defaultOrganizationId();
    const rows = await this.prisma.withContext({ organizationId }, (tx) =>
      tx.$queryRaw<LoginLookupRow[]>`SELECT user_id, password_hash FROM app.login_lookup(${login})`,
    );
    // Một chuỗi có thể trùng email của người này và số điện thoại của người khác: không đoán, từ chối.
    const found = rows.length === 1 ? rows[0] : undefined;
    const storedHash = found?.password_hash?.startsWith(SCRYPT_HASH_PREFIX) ? found.password_hash : undefined;
    const valid = await this.passwordChecks.run(() => this.passwordHasher.verify(password, storedHash));
    return valid && found && storedHash ? { userId: found.user_id, organizationId } : null;
  }
}
