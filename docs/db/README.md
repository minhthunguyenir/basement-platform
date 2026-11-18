# Basement – Cơ sở dữ liệu

Lược đồ PostgreSQL của Basement, nền tảng quản lý chuỗi không gian tự học kết hợp thư viện. Gồm 25 bảng, phân quyền theo tổ chức và chi nhánh bằng Row-Level Security (RLS), và tìm sách bằng vector (pgvector).

## Thư mục `db/`

| File | Nội dung | Chạy bằng |
|---|---|---|
| `01_schema.sql` | Extension, 18 enum, 25 bảng, khóa chính, khóa ngoại, CHECK, index một phần, index thường | `basement_owner` |
| `02_triggers.sql` | Hàm `set_updated_at()` và 22 trigger tự cập nhật `updated_at` | `basement_owner` |
| `03_rls.sql` | Vai trò DB, hàm hỗ trợ trong schema `app`, bật RLS cho 25 bảng, 116 policy | superuser |
| `04_rls_tests.sql` | 50 ca kiểm thử RLS. Tự `ROLLBACK` nên không để lại dữ liệu | superuser |
| `basement.dbml` | Bản thiết kế dạng DBML, mở bằng [dbdiagram.io](https://dbdiagram.io) để xem sơ đồ | — |

**Phải chạy đúng thứ tự 01 → 02 → 03 → 04.** Mỗi file bọc trong `BEGIN … COMMIT`, nên lỗi giữa chừng thì file đó không tạo gì cả.

## Yêu cầu

- PostgreSQL **16 trở lên**. Thiết kế dùng `NULLS NOT DISTINCT`, cú pháp này có từ bản 15.
- Extension **pgvector 0.5 trở lên** (cần cho HNSW index) và **btree_gist** (có sẵn trong gói contrib của PostgreSQL).
- `psql` ở máy chạy lệnh.
- Một tài khoản **superuser**. Tài khoản này cần để tạo extension và tạo các vai trò `basement_security`, `basement_app`.

Cách nhanh nhất là dùng Docker image `pgvector/pgvector:pg16`, đã có sẵn cả hai extension.

## Chạy lần đầu

### Bước 1. Khởi động PostgreSQL (nếu dùng Docker)

Chạy từ thư mục gốc của repo, thư mục chứa `db/`:

```bash
docker run -d --name basement-db \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  -v "$PWD/db:/sql" \
  pgvector/pgvector:pg16
```

Trong container, 4 file SQL nằm ở `/sql`. Các lệnh `psql` bên dưới chạy bên trong container:

```bash
alias bpsql='docker exec -i basement-db psql -U postgres -v ON_ERROR_STOP=1'
```

Nếu bạn cài PostgreSQL trực tiếp trên máy, thay `bpsql` bằng `psql -U postgres -v ON_ERROR_STOP=1`, và thay đường dẫn `/sql/...` bằng `db/...`.

### Bước 2. Tạo database, vai trò migration và extension (superuser)

```bash
bpsql -c "CREATE ROLE basement_owner LOGIN PASSWORD 'doi_mat_khau_nay';"
bpsql -c "CREATE DATABASE basement OWNER basement_owner;"
bpsql -d basement -c "CREATE EXTENSION IF NOT EXISTS btree_gist;" \
                  -c "CREATE EXTENSION IF NOT EXISTS vector;" \
                  -c "GRANT CREATE ON SCHEMA public TO basement_owner;"
```

Extension phải được tạo bằng superuser. Khi `01_schema.sql` chạy, hai dòng `CREATE EXTENSION IF NOT EXISTS` trong file sẽ bỏ qua vì extension đã có sẵn.

### Bước 3. Tạo bảng và trigger (dưới vai trò `basement_owner`)

```bash
bpsql -d basement -c "SET ROLE basement_owner" -f /sql/01_schema.sql -f /sql/02_triggers.sql
```

`SET ROLE` giúp mọi bảng thuộc về `basement_owner` thay vì `postgres`.

### Bước 4. Bật RLS và tạo vai trò ứng dụng (superuser)

```bash
bpsql -d basement -f /sql/03_rls.sql
bpsql -c "ALTER ROLE basement_app PASSWORD 'doi_mat_khau_nay';"
```

### Bước 5. Chạy kiểm thử RLS

```bash
bpsql -d basement -f /sql/04_rls_tests.sql
```

Kết quả đúng là bảng 50 dòng, dòng nào cũng `ĐẠT`, dòng cuối ghi **`50/50 ca đạt`**. Có dòng `LỖI` thì xem cột `thuc_te` để biết lỗi gì, rồi tra mục [Lỗi thường gặp](#lỗi-thường-gặp).

### Kiểm tra nhanh sau khi chạy

```sql
-- 25 bảng, tất cả bật và ép RLS
SELECT count(*) AS so_bang,
       count(*) FILTER (WHERE relrowsecurity AND relforcerowsecurity) AS bat_rls
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r';
-- Kết quả mong đợi: 25 | 25
```

## Chạy lại từ đầu

Vai trò DB thuộc cả cụm PostgreSQL, không thuộc riêng database. Vì vậy khi chạy lại, phải xóa database trước rồi mới xóa vai trò:

```bash
bpsql -c "DROP DATABASE IF EXISTS basement;"
bpsql -c "DROP ROLE IF EXISTS basement_app;" \
      -c "DROP ROLE IF EXISTS basement_security;" \
      -c "DROP ROLE IF EXISTS basement_owner;"
```

Sau đó làm lại từ Bước 2. Riêng `04_rls_tests.sql` thì chạy lại bao nhiêu lần cũng được, không cần dọn dữ liệu.

## Ba vai trò DB

| Vai trò | Đăng nhập | Dùng để |
|---|---|---|
| `basement_owner` | có | Chạy migration, sở hữu bảng. Bảng bật `FORCE ROW LEVEL SECURITY`, nên vai trò này cũng bị RLS lọc khi đọc ghi dữ liệu. |
| `basement_security` | không | Chỉ sở hữu các hàm `SECURITY DEFINER` trong schema `app`. Có `BYPASSRLS` để các hàm này đọc được `user_roles` mà không bị RLS gọi đệ quy. |
| `basement_app` | có | **Ứng dụng NestJS chỉ kết nối bằng vai trò này.** Không phải superuser, không sở hữu bảng, không có `BYPASSRLS`. Không có quyền xóa dòng (xóa mềm hoặc hủy bằng trạng thái) và không đọc được `users.password_hash`. |

**Không** cho ứng dụng kết nối bằng `postgres` hay `basement_owner`: superuser bỏ qua RLS, nên mọi phân quyền sẽ mất tác dụng.

## Ứng dụng kết nối thế nào

Trong **mỗi giao dịch**, ứng dụng phải gán tổ chức và người dùng hiện tại trước khi truy vấn:

```sql
BEGIN;
SELECT set_config('app.organization_id', '<uuid tổ chức>', true),
       set_config('app.user_id',         '<uuid người dùng, hoặc chuỗi rỗng nếu chưa đăng nhập>', true);
-- ... các truy vấn của request ...
COMMIT;
```

- Tham số thứ ba là `true`, nghĩa là giá trị chỉ có hiệu lực trong giao dịch hiện tại. **Bắt buộc dùng cách này khi có connection pool**: nếu gán theo phiên, request sau có thể dùng nhầm ngữ cảnh của request trước.
- Chưa gán `app.organization_id` thì mọi bảng trả 0 dòng. Hệ thống đóng theo mặc định.
- Một số việc phải gọi qua hàm thay vì đọc bảng trực tiếp:

| Hàm | Dùng khi |
|---|---|
| `app.branch_occupancy()` | Xem số chỗ trống từng chi nhánh, kể cả khi chưa đăng nhập |
| `app.customer_active_session(customer_id)` | Nhân viên tra xem khách đang có phiên mở ở chi nhánh nào |
| `app.login_lookup(email_hoặc_sđt)` | Lấy `password_hash` để kiểm tra mật khẩu khi đăng nhập |
| `app.register_customer(...)` | Khách tự đăng ký. Trùng số điện thoại với khách vãng lai thì nâng cấp chính dòng đó |

## Quy ước thiết kế (tóm tắt)

- Khóa chính `id uuid DEFAULT gen_random_uuid()`. Tên bảng và cột viết `snake_case`, tên bảng ở dạng số nhiều.
- Bảng nào cũng có `organization_id NOT NULL`, trừ `organizations`.
- `branch_id` có bốn loại:

| Loại `branch_id` | Ý nghĩa | Ví dụ |
|---|---|---|
| NOT NULL | dữ liệu của một chi nhánh | `seat_sessions`, `invoices` |
| NULL được | NULL = toàn chuỗi | `announcements`, `ideas` |
| Không có | dữ liệu cấp tổ chức | `users`, `books` |
| Kế thừa | phạm vi lấy theo bảng cha | `idea_comments`, `announcement_reads` |

- Khóa ngoại kép kèm `organization_id` hoặc `branch_id`, để bản ghi cha luôn cùng tổ chức, cùng chi nhánh với bản ghi con.
- Bảng danh mục và cấu hình xóa mềm bằng `deleted_at`. Bảng giao dịch dùng cột trạng thái và bắt buộc ghi lý do khi hủy.
- Tiền lưu kiểu `bigint`, đơn vị đồng.
- Số chỗ trống không lưu thành cột: chỗ trống = `capacity` − số phiên `active`.

Danh sách đầy đủ 25 bảng và sơ đồ ERD nằm trong hai trang Claude "Basement – Danh sách 25 bảng CSDL" và "Basement – ERD (mức logic)". Nhờ người quản lý repo chia sẻ link cho bạn.

## Lỗi thường gặp

| Thông báo lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `type "vector" does not exist` hoặc `extension "vector" is not available` | Máy chưa cài pgvector | Dùng image `pgvector/pgvector:pg16`, hoặc cài gói pgvector cho PostgreSQL 16 |
| `permission denied to create extension` | Tạo extension bằng vai trò không phải superuser | Làm lại Bước 2 bằng `postgres` |
| `permission denied for schema public` | Thiếu `GRANT CREATE ON SCHEMA public TO basement_owner` | Chạy lại lệnh GRANT ở Bước 2 |
| `permission denied to create role` hoặc lỗi khi `ALTER FUNCTION … OWNER TO basement_security` | Chạy `03_rls.sql` bằng `basement_owner` | Chạy `03_rls.sql` bằng `postgres` (Bước 4) |
| `policy "org_isolation" ... already exists` | Chạy `03_rls.sql` lần thứ hai | Làm theo mục [Chạy lại từ đầu](#chạy-lại-từ-đầu) |
| `04_rls_tests.sql` báo `duplicate key` ngay từ đầu | Database đã có dữ liệu thật trùng mã với dữ liệu mẫu | Chạy kiểm thử trên một database sạch |
| Ứng dụng không thấy dòng nào | Chưa gán `app.organization_id` trong giao dịch, hoặc người dùng không có vai trò ở chi nhánh đó | Kiểm tra `set_config` ở đầu giao dịch và bảng `user_roles` |

## Ghi chú

- **HNSW index cho vector chưa được tạo.** Mẫu lệnh nằm cuối `01_schema.sql`, ở dạng chú thích. Khi đã chốt tên và số chiều của từng mô hình embedding, mỗi mô hình tạo một index riêng.
- **Các quy tắc liên bảng do service xử lý, không có trigger trong DB**, ví dụ:
  - xác nhận thanh toán thì chuyển hóa đơn sang `paid`;
  - trừ tồn kho khi xác nhận đơn;
  - cập nhật `book_copies.status` khi mượn, trả.
- 4 file đã được chạy thử trên PostgreSQL 16. Phần pgvector khi thử được thay bằng một kiểu tương đương, nên lần đầu chạy trên máy có pgvector thật, hãy để ý kết quả của `01_schema.sql`.
- Đổi lược đồ thì sửa file SQL tương ứng, đồng thời sửa `basement.dbml` để hai bản luôn khớp nhau.
