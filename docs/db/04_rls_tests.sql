-- 04_rls_tests.sql — Basement: kiểm thử Row-Level Security
-- Chạy sau 01, 02, 03 bằng tài khoản quản trị (superuser hoặc BYPASSRLS) để nạp dữ liệu mẫu;
-- các phép thử chạy dưới vai trò basement_app (SET ROLE). Cả file nằm trong một giao dịch
-- và ROLLBACK ở cuối: không để lại dữ liệu.
-- Kết quả: mỗi dòng "ĐẠT/LỖI | mã ca | mô tả | mong đợi | thực tế".

\set ON_ERROR_STOP 1
\pset footer off
BEGIN;

-- ===========================================================================
-- 0. Công cụ kiểm thử (schema tạm rls_test)
-- ===========================================================================
CREATE SCHEMA rls_test;
CREATE TABLE rls_test.results (seq serial, code text, label text, expected text, actual text, ok boolean);
GRANT USAGE ON SCHEMA rls_test TO basement_app;
GRANT INSERT, SELECT ON rls_test.results TO basement_app;
GRANT USAGE ON SEQUENCE rls_test.results_seq_seq TO basement_app;

-- Gán ngữ cảnh giống ứng dụng (đặt ở mức phiên để dùng qua nhiều câu lệnh trong file).
CREATE FUNCTION rls_test.act_as(p_org uuid, p_user uuid) RETURNS void LANGUAGE sql AS $$
    SELECT set_config('app.organization_id', coalesce(p_org::text, ''), false),
           set_config('app.user_id', coalesce(p_user::text, ''), false);
$$;

-- Đếm số dòng câu truy vấn trả về, so với số mong đợi.
CREATE FUNCTION rls_test.expect_rows(p_code text, p_label text, p_expected bigint, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
    EXECUTE format('SELECT count(*) FROM (%s) q', p_sql) INTO n;
    INSERT INTO rls_test.results (code, label, expected, actual, ok)
    VALUES (p_code, p_label, p_expected || ' dòng', n || ' dòng', n = p_expected);
EXCEPTION WHEN others THEN
    INSERT INTO rls_test.results (code, label, expected, actual, ok)
    VALUES (p_code, p_label, p_expected || ' dòng', 'lỗi ' || SQLSTATE || ': ' || left(SQLERRM, 80), false);
END $$;

-- Câu lệnh phải bị từ chối đúng lý do: vi phạm policy RLS, hoặc không có quyền trên bảng/cột.
-- Lỗi khác (vd. sai cú pháp, thiếu quyền gọi hàm) bị tính là LỖI để không đạt nhầm.
CREATE FUNCTION rls_test.expect_error(p_code text, p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        INSERT INTO rls_test.results (code, label, expected, actual, ok)
        VALUES (p_code, p_label, 'bị từ chối (RLS/quyền)', 'chạy được', false);
    EXCEPTION WHEN others THEN
        INSERT INTO rls_test.results (code, label, expected, actual, ok)
        VALUES (p_code, p_label, 'bị từ chối (RLS/quyền)', SQLSTATE || ': ' || left(SQLERRM, 80),
                SQLSTATE = '42501' AND (SQLERRM LIKE '%row-level security%' OR SQLERRM LIKE 'permission denied for table%'));
    END;
END $$;

-- UPDATE phải không chạm dòng nào (RLS ẩn dòng nên số dòng bị ảnh hưởng = 0).
CREATE FUNCTION rls_test.expect_no_update(p_code text, p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS n = ROW_COUNT;
    INSERT INTO rls_test.results (code, label, expected, actual, ok)
    VALUES (p_code, p_label, '0 dòng bị sửa', n || ' dòng bị sửa', n = 0);
EXCEPTION WHEN others THEN
    INSERT INTO rls_test.results (code, label, expected, actual, ok)
    VALUES (p_code, p_label, '0 dòng bị sửa', 'lỗi ' || SQLSTATE || ': ' || left(SQLERRM, 80), false);
END $$;

-- Câu lệnh hợp lệ phải chạy được.
CREATE FUNCTION rls_test.expect_ok(p_code text, p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    INSERT INTO rls_test.results (code, label, expected, actual, ok)
    VALUES (p_code, p_label, 'chạy được', 'chạy được', true);
EXCEPTION WHEN others THEN
    INSERT INTO rls_test.results (code, label, expected, actual, ok)
    VALUES (p_code, p_label, 'chạy được', 'lỗi ' || SQLSTATE || ': ' || left(SQLERRM, 80), false);
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA rls_test TO basement_app;

-- ===========================================================================
-- 1. Dữ liệu mẫu (nạp bằng tài khoản quản trị, không qua RLS)
--    Tổ chức A: chi nhánh A1, A2. Tổ chức B: chi nhánh B1.
-- ===========================================================================
INSERT INTO organizations (id, name, slug) VALUES
 ('a0000000-0000-0000-0000-000000000000', 'Basement', 'basement'),
 ('b0000000-0000-0000-0000-000000000000', 'Chuỗi khác', 'other');
INSERT INTO branches (id, organization_id, code, name, capacity) VALUES
 ('a1000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000', 'A1', 'TP.HCM', 40),
 ('a2000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000', 'A2', 'Đà Nẵng', 30),
 ('b1000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000000', 'B1', 'Chi nhánh B', 20);

-- Người dùng tổ chức A: chủ (toàn chuỗi), quản lý A1, nhân viên A1, nhân viên A2, 2 khách.
-- Tổ chức B: 1 nhân viên.
INSERT INTO users (id, organization_id, full_name, phone, email, password_hash, member_code) VALUES
 ('a0000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-000000000000', 'Chủ A',       '0901', 'owner@a', 'h', 'MA01'),
 ('a0000000-0000-0000-0000-0000000000f2', 'a0000000-0000-0000-0000-000000000000', 'Quản lý A1',  '0902', 'mgr1@a',  'h', 'MA02'),
 ('a0000000-0000-0000-0000-0000000000f3', 'a0000000-0000-0000-0000-000000000000', 'NV A1',       '0903', 'st1@a',   'h', 'MA03'),
 ('a0000000-0000-0000-0000-0000000000f4', 'a0000000-0000-0000-0000-000000000000', 'NV A2',       '0904', 'st2@a',   'h', 'MA04'),
 ('a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-000000000000', 'Khách 1',     '0905', 'c1@a',    'h', 'MA05'),
 ('a0000000-0000-0000-0000-0000000000c2', 'a0000000-0000-0000-0000-000000000000', 'Khách 2',     '0906', 'c2@a',    'h', 'MA06'),
 ('b0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-000000000000', 'NV B1',       '0907', 'st@b',    'h', 'MB01');
INSERT INTO user_roles (organization_id, user_id, branch_id, role) VALUES
 ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f1', NULL, 'owner'),
 ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f2', 'a1000000-0000-0000-0000-000000000000', 'branch_manager'),
 ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f3', 'a1000000-0000-0000-0000-000000000000', 'staff'),
 ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f4', 'a2000000-0000-0000-0000-000000000000', 'staff'),
 ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000c1', NULL, 'customer'),
 ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000c2', NULL, 'customer'),
 ('b0000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-0000000000f1', 'b1000000-0000-0000-0000-000000000000', 'staff');

-- Phiên: khách 1 ở A1 (đang mở), khách 2 ở A2 (đã đóng), một phiên ở B1.
INSERT INTO seat_sessions (id, organization_id, branch_id, customer_id, seating_type, opened_by) VALUES
 ('a0000000-0000-0000-0000-000000000501', 'a0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000',
  'a0000000-0000-0000-0000-0000000000c1', 'laptop', 'a0000000-0000-0000-0000-0000000000f3');
INSERT INTO seat_sessions (id, organization_id, branch_id, customer_id, seating_type, opened_by, started_at,
                           status, ended_at, closed_at, close_type, closed_by) VALUES
 ('a0000000-0000-0000-0000-000000000502', 'a0000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
  'a0000000-0000-0000-0000-0000000000c2', 'no_laptop', 'a0000000-0000-0000-0000-0000000000f4', now() - interval '3 hours',
  'closed', now() - interval '1 hour', now() - interval '1 hour', 'normal', 'a0000000-0000-0000-0000-0000000000f4');
INSERT INTO seat_sessions (id, organization_id, branch_id, customer_id, seating_type, opened_by) VALUES
 ('b0000000-0000-0000-0000-000000000501', 'b0000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000000',
  'b0000000-0000-0000-0000-0000000000f1', 'laptop', 'b0000000-0000-0000-0000-0000000000f1');

-- Hóa đơn và thanh toán của khách 2 ở A2.
INSERT INTO invoices (id, organization_id, branch_id, customer_id, seat_session_id, code, seat_amount, total_amount, created_by) VALUES
 ('a0000000-0000-0000-0000-000000000e01', 'a0000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
  'a0000000-0000-0000-0000-0000000000c2', 'a0000000-0000-0000-0000-000000000502', 'HD-A2-1', 8000, 8000,
  'a0000000-0000-0000-0000-0000000000f4');
INSERT INTO payments (organization_id, branch_id, invoice_id, method, amount, status, created_by, confirmed_by, confirmed_at) VALUES
 ('a0000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000e01',
  'cash', 8000, 'confirmed', 'a0000000-0000-0000-0000-0000000000f4', 'a0000000-0000-0000-0000-0000000000f4', now());

-- Sản phẩm, sách của tổ chức A và B.
INSERT INTO products (organization_id, name, category, default_price) VALUES
 ('a0000000-0000-0000-0000-000000000000', 'Nước suối', 'drink', 6000),
 ('b0000000-0000-0000-0000-000000000000', 'Nước B', 'drink', 6000);

-- Thông báo: toàn chuỗi cho tất cả; riêng A1 cho nhân viên; riêng A2 cho khách; một thông báo ở B.
INSERT INTO announcements (id, organization_id, branch_id, audience, title, body, created_by) VALUES
 ('a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000000', NULL, 'all', 'Khai trương', '...', 'a0000000-0000-0000-0000-0000000000f1'),
 ('a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000', 'staff', 'Họp ca A1', '...', 'a0000000-0000-0000-0000-0000000000f2'),
 ('a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'customers', 'Giảm giá A2', '...', 'a0000000-0000-0000-0000-0000000000f1'),
 ('b0000000-0000-0000-0000-000000000a01', 'b0000000-0000-0000-0000-000000000000', NULL, 'all', 'Thông báo B', '...', 'b0000000-0000-0000-0000-0000000000f1');
INSERT INTO announcements (organization_id, branch_id, audience, title, body, publish_at, created_by) VALUES
 ('a0000000-0000-0000-0000-000000000000', NULL, 'all', 'Lên lịch tuần sau', '...', now() + interval '7 days', 'a0000000-0000-0000-0000-0000000000f1');

-- Ý tưởng: A1 pending (NV A1), A2 resolved (NV A2), toàn chuỗi reviewing (NV A1).
INSERT INTO ideas (id, organization_id, branch_id, author_id, title, body, status, resolved_by, resolved_at) VALUES
 ('a0000000-0000-0000-0000-000000001d01', 'a0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000',
  'a0000000-0000-0000-0000-0000000000f3', 'Thêm ổ cắm', '...', 'pending', NULL, NULL),
 ('a0000000-0000-0000-0000-000000001d02', 'a0000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
  'a0000000-0000-0000-0000-0000000000f4', 'Đổi đèn', '...', 'resolved', 'a0000000-0000-0000-0000-0000000000f1', now()),
 ('a0000000-0000-0000-0000-000000001d03', 'a0000000-0000-0000-0000-000000000000', NULL,
  'a0000000-0000-0000-0000-0000000000f3', 'Ca đêm', '...', 'reviewing', NULL, NULL);

-- ===========================================================================
-- 2. Chạy các phép thử dưới vai trò ứng dụng
-- ===========================================================================
SET ROLE basement_app;

-- ---------- Nhóm X: chéo tổ chức ----------------------------------------------
SELECT rls_test.act_as('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f1');
SELECT rls_test.expect_rows('X1', 'Chủ A không thấy phiên ngồi của tổ chức B', 0,
    $$SELECT 1 FROM seat_sessions WHERE organization_id = 'b0000000-0000-0000-0000-000000000000'$$);
SELECT rls_test.expect_rows('X2', 'Chủ A không thấy sản phẩm của tổ chức B', 0,
    $$SELECT 1 FROM products WHERE organization_id = 'b0000000-0000-0000-0000-000000000000'$$);
SELECT rls_test.expect_rows('X3', 'Chủ A chỉ thấy đúng 1 tổ chức (của mình)', 1, $$SELECT 1 FROM organizations$$);
SELECT rls_test.expect_error('X4', 'Chủ A ghi sản phẩm mang organization_id của B',
    $$INSERT INTO products (organization_id, name, category, default_price)
      VALUES ('b0000000-0000-0000-0000-000000000000', 'Lén', 'drink', 1)$$);
SELECT rls_test.expect_no_update('X5', 'Chủ A sửa chi nhánh B1',
    $$UPDATE branches SET capacity = 1 WHERE id = 'b1000000-0000-0000-0000-000000000000'$$);

-- Đổi app.organization_id sang B nhưng vẫn là người dùng của A (giả mạo ngữ cảnh).
SELECT rls_test.act_as('b0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f1');
SELECT rls_test.expect_rows('X6', 'Chủ A gán ngữ cảnh sang tổ chức B: không thấy phiên nào (không có vai trò ở B)', 0,
    $$SELECT 1 FROM seat_sessions$$);
SELECT rls_test.expect_error('X7', 'Chủ A gán ngữ cảnh B rồi mở phiên ở B1',
    $$INSERT INTO seat_sessions (organization_id, branch_id, customer_id, seating_type, opened_by)
      VALUES ('b0000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000000',
              'b0000000-0000-0000-0000-0000000000f1', 'laptop', 'a0000000-0000-0000-0000-0000000000f1')$$);

-- Không gán ngữ cảnh: đóng mặc định.
SELECT rls_test.act_as(NULL, NULL);
SELECT rls_test.expect_rows('X8', 'Không có app.organization_id: users trả 0 dòng', 0, $$SELECT 1 FROM users$$);
SELECT rls_test.expect_rows('X9', 'Không có app.organization_id: branches trả 0 dòng', 0, $$SELECT 1 FROM branches$$);

-- ---------- Nhóm C: chéo chi nhánh --------------------------------------------
SELECT rls_test.act_as('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f3');  -- NV A1
SELECT rls_test.expect_rows('C1', 'NV A1 chỉ thấy phiên của A1', 1, $$SELECT 1 FROM seat_sessions$$);
SELECT rls_test.expect_rows('C2', 'NV A1 không thấy hóa đơn của A2', 0, $$SELECT 1 FROM invoices$$);
SELECT rls_test.expect_rows('C3', 'NV A1 không thấy thanh toán của A2', 0, $$SELECT 1 FROM payments$$);
SELECT rls_test.expect_error('C4', 'NV A1 mở phiên ở chi nhánh A2',
    $$INSERT INTO seat_sessions (organization_id, branch_id, customer_id, seating_type, opened_by)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
              'a0000000-0000-0000-0000-0000000000c2', 'laptop', 'a0000000-0000-0000-0000-0000000000f3')$$);
SELECT rls_test.expect_no_update('C5', 'NV A1 hủy hóa đơn của A2',
    $$UPDATE invoices SET status = 'cancelled', cancel_reason = 'x', cancelled_by = 'a0000000-0000-0000-0000-0000000000f3'
      WHERE id = 'a0000000-0000-0000-0000-000000000e01'$$);
SELECT rls_test.expect_rows('C6', 'NV A1 thấy thông báo toàn chuỗi + thông báo nhân viên A1 (không thấy bài của A2, bài chưa đến giờ)', 2,
    $$SELECT 1 FROM announcements$$);
SELECT rls_test.expect_rows('C7', 'NV A1 thấy ý tưởng: A1 pending (của mình) + toàn chuỗi; không thấy ý tưởng A2', 2,
    $$SELECT 1 FROM ideas$$);
SELECT rls_test.expect_rows('C8', 'NV A1 xem được khách toàn tổ chức để quét mã (users của tổ chức A)', 6,
    $$SELECT 1 FROM users$$);
SELECT rls_test.expect_rows('C9', 'NV A1 dùng hàm tra phiên mở của khách 1 (đang ở A1)', 1,
    $$SELECT * FROM app.customer_active_session('a0000000-0000-0000-0000-0000000000c1')$$);

SELECT rls_test.act_as('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f4');  -- NV A2
SELECT rls_test.expect_rows('C10', 'NV A2 không thấy ý tưởng pending của NV A1 ở A1', 0,
    $$SELECT 1 FROM ideas WHERE id = 'a0000000-0000-0000-0000-000000001d01'$$);
SELECT rls_test.expect_error('C11', 'NV A2 bình luận vào ý tưởng của A1 (bảng kế thừa, EXISTS tới bảng cha)',
    $$INSERT INTO idea_comments (organization_id, idea_id, author_id, body)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000001d01',
              'a0000000-0000-0000-0000-0000000000f4', 'x')$$);
SELECT rls_test.expect_rows('C12', 'NV A2 không đọc trực tiếp được phiên của khách 1 ở A1', 0,
    $$SELECT 1 FROM seat_sessions WHERE customer_id = 'a0000000-0000-0000-0000-0000000000c1'$$);
SELECT rls_test.expect_rows('C13', 'NV A2 vẫn biết khách 1 đang có phiên mở (qua hàm, chỉ lộ chi nhánh và giờ)', 1,
    $$SELECT * FROM app.customer_active_session('a0000000-0000-0000-0000-0000000000c1')$$);

SELECT rls_test.act_as('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f2');  -- Quản lý A1
SELECT rls_test.expect_no_update('C14', 'Quản lý A1 sửa sức chứa chi nhánh A2',
    $$UPDATE branches SET capacity = 1 WHERE id = 'a2000000-0000-0000-0000-000000000000'$$);
SELECT rls_test.expect_error('C15', 'Quản lý A1 cấp vai trò staff ở A2',
    $$INSERT INTO user_roles (organization_id, user_id, branch_id, role)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000c2',
              'a2000000-0000-0000-0000-000000000000', 'staff')$$);
SELECT rls_test.expect_error('C16', 'Quản lý A1 tự cấp vai trò owner',
    $$INSERT INTO user_roles (organization_id, user_id, branch_id, role)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f2', NULL, 'owner')$$);
SELECT rls_test.expect_ok('C17', 'Quản lý A1 cấp vai trò staff ở A1',
    $$INSERT INTO user_roles (organization_id, user_id, branch_id, role)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000c2',
              'a1000000-0000-0000-0000-000000000000', 'staff')$$);
SELECT rls_test.expect_error('C18', 'Quản lý A1 đăng thông báo toàn chuỗi (branch_id NULL)',
    $$INSERT INTO announcements (organization_id, branch_id, audience, title, body, created_by)
      VALUES ('a0000000-0000-0000-0000-000000000000', NULL, 'all', 'x', 'y', 'a0000000-0000-0000-0000-0000000000f2')$$);

SELECT rls_test.act_as('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000f1');  -- Chủ A
SELECT rls_test.expect_rows('C19', 'Chủ A (vai trò toàn chuỗi) thấy phiên của cả A1 và A2', 2, $$SELECT 1 FROM seat_sessions$$);
SELECT rls_test.expect_rows('C20', 'Chủ A thấy cả 3 ý tưởng, kể cả pending', 3, $$SELECT 1 FROM ideas$$);
SELECT rls_test.expect_rows('C21', 'Chủ A thấy cả thông báo đã lên lịch (người soạn)', 4, $$SELECT 1 FROM announcements$$);

-- ---------- Nhóm K: khách chỉ thấy dữ liệu của mình ------------------------------
SELECT rls_test.act_as('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000c1');  -- Khách 1
SELECT rls_test.expect_rows('K1', 'Khách 1 chỉ thấy phiên của mình', 1, $$SELECT 1 FROM seat_sessions$$);
SELECT rls_test.expect_rows('K2', 'Khách 1 không thấy hóa đơn của khách 2', 0, $$SELECT 1 FROM invoices$$);
SELECT rls_test.expect_rows('K3', 'Khách 1 không thấy thanh toán của khách 2', 0, $$SELECT 1 FROM payments$$);
SELECT rls_test.expect_rows('K4', 'Khách 1 chỉ thấy chính mình trong users', 1, $$SELECT 1 FROM users$$);
SELECT rls_test.expect_rows('K5', 'Khách 1 không thấy bảng ý tưởng', 0, $$SELECT 1 FROM ideas$$);
SELECT rls_test.expect_rows('K6', 'Khách 1 không đọc được nhật ký tìm kiếm', 0, $$SELECT 1 FROM book_search_logs$$);
SELECT rls_test.expect_rows('K7', 'Khách 1 thấy thông báo toàn chuỗi + thông báo khách của A2 (không thấy bài nhân viên)', 2,
    $$SELECT 1 FROM announcements$$);
SELECT rls_test.expect_error('K8', 'Khách 1 đọc cột password_hash',
    $$SELECT password_hash FROM users$$);
SELECT rls_test.expect_error('K9', 'Khách 1 tự mở phiên ngồi',
    $$INSERT INTO seat_sessions (organization_id, branch_id, customer_id, seating_type, opened_by)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000',
              'a0000000-0000-0000-0000-0000000000c1', 'laptop', 'a0000000-0000-0000-0000-0000000000c1')$$);
SELECT rls_test.expect_error('K10', 'Khách 1 xác nhận đã đọc thông báo dành cho nhân viên',
    $$INSERT INTO announcement_reads (organization_id, announcement_id, user_id)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000a02',
              'a0000000-0000-0000-0000-0000000000c1')$$);
SELECT rls_test.expect_error('K11', 'Khách 1 xác nhận đã đọc thay cho khách 2',
    $$INSERT INTO announcement_reads (organization_id, announcement_id, user_id)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000a01',
              'a0000000-0000-0000-0000-0000000000c2')$$);
SELECT rls_test.expect_ok('K12', 'Khách 1 xác nhận đã đọc thông báo toàn chuỗi',
    $$INSERT INTO announcement_reads (organization_id, announcement_id, user_id)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000a01',
              'a0000000-0000-0000-0000-0000000000c1')$$);
SELECT rls_test.expect_ok('K13', 'Khách 1 ghi nhật ký tìm kiếm của chính mình',
    $$INSERT INTO book_search_logs (organization_id, user_id, query_text, search_mode, latency_ms)
      VALUES ('a0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-0000000000c1', 'sách tâm lý', 'fts', 12)$$);
SELECT rls_test.expect_no_update('K14', 'Khách 1 sửa hồ sơ của khách 2',
    $$UPDATE users SET full_name = 'x' WHERE id = 'a0000000-0000-0000-0000-0000000000c2'$$);
SELECT rls_test.expect_rows('K15', 'Khách 1 xem số chỗ trống 2 chi nhánh qua hàm (không lộ phiên của ai)', 2,
    $$SELECT * FROM app.branch_occupancy()$$);
SELECT rls_test.expect_rows('K16', 'Khách 1 gọi hàm tra phiên mở của khách khác: không có kết quả (chỉ nhân viên)', 0,
    $$SELECT * FROM app.customer_active_session('a0000000-0000-0000-0000-0000000000c2')$$);

-- Khách chưa đăng nhập (có tổ chức, chưa có user).
SELECT rls_test.act_as('a0000000-0000-0000-0000-000000000000', NULL);
SELECT rls_test.expect_rows('K17', 'Chưa đăng nhập: xem được số chỗ trống', 2, $$SELECT * FROM app.branch_occupancy()$$);
SELECT rls_test.expect_rows('K18', 'Chưa đăng nhập: không thấy phiên ngồi nào', 0, $$SELECT 1 FROM seat_sessions$$);
SELECT rls_test.expect_rows('K19', 'Chưa đăng nhập: không thấy thông báo', 0, $$SELECT 1 FROM announcements$$);
SELECT rls_test.expect_rows('K20', 'Đăng nhập bằng email lấy được hash qua hàm', 1,
    $$SELECT * FROM app.login_lookup('c1@a')$$);

RESET ROLE;

-- ===========================================================================
-- 3. Kết quả
-- ===========================================================================
SELECT CASE WHEN ok THEN 'ĐẠT' ELSE 'LỖI' END AS kq, code AS ca, label AS mo_ta, expected AS mong_doi, actual AS thuc_te
FROM rls_test.results ORDER BY seq;
SELECT count(*) FILTER (WHERE ok) || '/' || count(*) || ' ca đạt' AS tong_ket FROM rls_test.results;

ROLLBACK;

-- Giả định
-- 1. Chạy bằng tài khoản quản trị (superuser hoặc BYPASSRLS) để nạp dữ liệu mẫu; phép thử chạy dưới SET ROLE basement_app.
-- 2. Ngữ cảnh gán ở mức phiên (set_config(..., false)) chỉ để tiện kiểm thử; ứng dụng thật gán ở mức giao dịch.
-- 3. Cả file ROLLBACK ở cuối nên chạy lại nhiều lần được, không cần dọn dữ liệu.
-- 4. UPDATE vào dòng bị RLS ẩn không báo lỗi mà sửa 0 dòng; ca "0 dòng bị sửa" là kết quả đúng.
