// set-dev-passwords.mjs: đặt mật khẩu cho các tài khoản seed (dev/staging), lấy từ SEED_USER_PASSWORD.
// Chạy: pnpm --filter @basement/api db:set-dev-passwords   (sau db:seed; dùng DIRECT_URL như db:seed)
// Mật khẩu không nằm trong repo, chỉ đặt trong apps/api/.env. Dev và staging dùng chung một mật khẩu (chỉ có dữ liệu mẫu);
// đổi mật khẩu staging trước khi cho người dùng thật (thử nghiệm SUS, demo) sử dụng.
// Chỉ đụng tới các tài khoản seed có member_code bên dưới; khách vãng lai không có mật khẩu.
import 'dotenv/config';
import prismaClient from '@prisma/client';
import { PasswordHasher } from '@nestjs/authentication';

const SEED_ORGANIZATION_ID = '00000000-0000-4000-a000-000000000001';
const SEED_MEMBER_CODES = ['BSM-0001', 'BSM-0002', 'BSM-0003', 'BSM-0004', 'BSM-0005', 'BSM-0011', 'BSM-0012', 'BSM-0013'];
const MIN_PASSWORD_LENGTH = 12;

function fail(message) {
  console.error(`Lỗi: ${message}`);
  process.exit(1);
}

const password = process.env.SEED_USER_PASSWORD;
if (!password || password.length < MIN_PASSWORD_LENGTH) {
  fail(`SEED_USER_PASSWORD chưa được đặt hoặc ngắn hơn ${MIN_PASSWORD_LENGTH} ký tự.`);
}
const url = process.env.DIRECT_URL;
if (!url) {
  fail('DIRECT_URL chưa được đặt (cần owner/superuser, như khi chạy db:seed).');
}

const prisma = new prismaClient.PrismaClient({ datasourceUrl: url });
const hasher = new PasswordHasher();

try {
  const users = await prisma.$queryRaw`
    SELECT id, member_code, coalesce(email, phone) AS login
    FROM users
    WHERE organization_id = ${SEED_ORGANIZATION_ID}::uuid
      AND member_code = ANY(${SEED_MEMBER_CODES})
      AND NOT is_guest AND deleted_at IS NULL
    ORDER BY member_code`;
  if (users.length === 0) {
    fail('Không tìm thấy tài khoản seed nào. Chạy db:seed trước.');
  }
  for (const user of users) {
    const hash = await hasher.hash(password);
    await prisma.$executeRaw`UPDATE users SET password_hash = ${hash} WHERE id = ${user.id}::uuid`;
    console.log(`  ${user.member_code}  ${user.login}`);
  }
  console.log(`Đã đặt mật khẩu cho ${users.length} tài khoản seed.`);
} finally {
  await prisma.$disconnect();
}
