import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { Client } = require('pg');

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const envPath = path.join(currentDir, '../.env');
if (fs.existsSync(envPath) && typeof process.loadEnvFile === 'function') {
  process.loadEnvFile(envPath);
}

interface SeedBookItem {
  title: string;
  authors: string;
  isbn: string | null;
  language: string;
  description: string;
  categories: string[];
}

async function main() {
  const dbUrl = process.env.DIRECT_URL || process.env.DATABASE_URL;
  if (!dbUrl) {
    throw new Error('Thiếu DIRECT_URL hoặc DATABASE_URL trong apps/api/.env');
  }

  const dataPath = path.join(currentDir, 'data/books.seed.json');
  if (!fs.existsSync(dataPath)) {
    throw new Error(`Không tìm thấy file ${dataPath}. Hãy chạy scripts/fetch-books.ts trước.`);
  }

  const rawBooks: SeedBookItem[] = JSON.parse(fs.readFileSync(dataPath, 'utf-8'));

  const client = new Client({ connectionString: dbUrl });
  await client.connect();

  try {
    // 1. Lấy tổ chức đầu tiên đã tạo từ seed.sql
    const orgRes = await client.query(
      'SELECT id, name FROM organizations WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1'
    );
    if (orgRes.rows.length === 0) {
      throw new Error('Không tìm thấy tổ chức nào trong DB. Hãy chạy seed.sql trước.');
    }
    const org = orgRes.rows[0];
    console.log(`Đang nạp kho sách cho tổ chức: ${org.name} (${org.id})`);

    // 2. Chỉ bỏ qua khi đã nạp đủ kho sách lớn (>= 300 cuốn); giữ nguyên 6 cuốn mẫu của seed.sql
    const countRes = await client.query(
      'SELECT COUNT(*)::int AS total FROM books WHERE organization_id = $1 AND deleted_at IS NULL',
      [org.id]
    );
    if (countRes.rows[0].total >= 300) {
      console.log(`Đã có ${countRes.rows[0].total} đầu sách trong DB, bỏ qua bước nạp lại.`);
      return;
    }

    // 3. Lấy danh sách chi nhánh
    const branchRes = await client.query(
      'SELECT id, code FROM branches WHERE organization_id = $1 AND deleted_at IS NULL ORDER BY code ASC',
      [org.id]
    );
    const branches = branchRes.rows;
    if (branches.length === 0) {
      throw new Error('Chưa có chi nhánh nào trong DB. Hãy chạy seed.sql trước.');
    }

    console.log(`Bắt đầu nạp bổ sung ${rawBooks.length} đầu sách vào ${branches.length} chi nhánh...`);
    const createdCopies: Array<{ id: string; branch_id: string }> = [];
    let insertedBooksCount = 0;

    // 4. Nạp đầu sách & bản sao (tự động bỏ qua nếu trùng ISBN hoặc barcode)
    for (let i = 0; i < rawBooks.length; i++) {
      const item = rawBooks[i];
      const bookInsert = await client.query(
        `INSERT INTO books (organization_id, title, authors, isbn, language, description, categories)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT DO NOTHING
         RETURNING id`,
        [org.id, item.title, item.authors, item.isbn, item.language, item.description, item.categories]
      );

      if (bookInsert.rows.length === 0) continue;
      insertedBooksCount++;
      const bookId = bookInsert.rows[0].id;

      const copiesCount = (i % 3) + 1;
      const bookSeq = String(i + 1).padStart(4, '0');

      for (let c = 0; c < copiesCount; c++) {
        const targetBranch = branches[(i + c) % branches.length];
        const copySeq = String(c + 1).padStart(2, '0');
        const barcode = `${targetBranch.code}-BK${bookSeq}-${copySeq}`;
        const status = i % 50 === 0 && c === 0 ? 'damaged' : 'available';

        const copyInsert = await client.query(
          `INSERT INTO book_copies (organization_id, branch_id, book_id, barcode, status)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT DO NOTHING
           RETURNING id`,
          [org.id, targetBranch.id, bookId, barcode, status]
        );

        if (copyInsert.rows.length > 0 && status === 'available') {
          createdCopies.push({ id: copyInsert.rows[0].id, branch_id: targetBranch.id });
        }
      }
    }

    // 5. Tạo thêm 6 phiếu mượn mẫu từ kho sách mới (đang mượn, quá hạn, đã trả)
    const staffRes = await client.query(
      `SELECT user_id FROM user_roles 
       WHERE organization_id = $1 AND role IN ('owner', 'branch_manager', 'staff') AND deleted_at IS NULL LIMIT 1`,
      [org.id]
    );
    const customerRes = await client.query(
      `SELECT user_id FROM user_roles 
       WHERE organization_id = $1 AND role = 'customer' AND deleted_at IS NULL LIMIT 1`,
      [org.id]
    );

    if (staffRes.rows.length > 0 && customerRes.rows.length > 0 && createdCopies.length >= 6) {
      const staffId = staffRes.rows[0].user_id;
      const customerId = customerRes.rows[0].user_id;
      const now = Date.now();
      const dayMs = 24 * 60 * 60 * 1000;

      const samples = [
        { idx: 0, status: 'active', loanedAt: new Date(now - 2 * dayMs), dueAt: new Date(now + 5 * dayMs), returnedAt: null, depStatus: 'held', fee: 0 },
        { idx: 1, status: 'active', loanedAt: new Date(now - 1 * dayMs), dueAt: new Date(now + 6 * dayMs), returnedAt: null, depStatus: 'held', fee: 0 },
        { idx: 2, status: 'active', loanedAt: new Date(now - 10 * dayMs), dueAt: new Date(now - 3 * dayMs), returnedAt: null, depStatus: 'held', fee: 0 },
        { idx: 3, status: 'active', loanedAt: new Date(now - 8 * dayMs), dueAt: new Date(now - 1 * dayMs), returnedAt: null, depStatus: 'held', fee: 0 },
        { idx: 4, status: 'returned', loanedAt: new Date(now - 14 * dayMs), dueAt: new Date(now - 7 * dayMs), returnedAt: new Date(now - 8 * dayMs), depStatus: 'refunded', fee: 0 },
        { idx: 5, status: 'returned', loanedAt: new Date(now - 12 * dayMs), dueAt: new Date(now - 7 * dayMs), returnedAt: new Date(now - 5 * dayMs), depStatus: 'refunded', fee: 10000 },
      ];

      for (const s of samples) {
        const copy = createdCopies[s.idx];
        await client.query(
          `INSERT INTO book_loans (
            organization_id, branch_id, book_copy_id, customer_id, loan_type, seat_session_id,
            status, loaned_at, due_at, returned_at, issued_by, received_by,
            deposit_amount, deposit_method, deposit_status, late_fee_amount
          ) VALUES ($1, $2, $3, $4, 'take_home', NULL, $5, $6, $7, $8, $9, $10, 50000, 'cash', $11, $12)`,
          [
            org.id,
            copy.branch_id,
            copy.id,
            customerId,
            s.status,
            s.loanedAt,
            s.dueAt,
            s.returnedAt,
            staffId,
            s.status === 'returned' ? staffId : null,
            s.depStatus,
            s.fee,
          ]
        );

        if (s.status === 'active') {
          await client.query(`UPDATE book_copies SET status = 'on_loan' WHERE id = $1`, [copy.id]);
        }
      }
    }

    const finalCount = await client.query(
      'SELECT COUNT(*)::int AS total FROM books WHERE organization_id = $1 AND deleted_at IS NULL',
      [org.id]
    );
    console.log(
      `Hoàn tất! Đã nạp thêm ${insertedBooksCount} đầu sách (Tổng hiện tại: ${finalCount.rows[0].total} đầu sách, ${createdCopies.length} bản sao sẵn sàng).`
    );
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error('Lỗi seed thư viện:', err);
  process.exit(1);
});