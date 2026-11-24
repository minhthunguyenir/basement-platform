-- seed.sql — Dữ liệu mẫu cho môi trường DEV/STAGING. KHÔNG chạy trên production.
-- Chạy bằng: pnpm --filter @basement/api db:seed   (dùng DIRECT_URL: owner/superuser, vượt RLS khi nạp)
-- Chạy lại nhiều lần được: mọi id cố định và INSERT ... ON CONFLICT (id) DO NOTHING.
-- Sau khi seed, đặt DEFAULT_ORGANIZATION_ID=00000000-0000-4000-a000-000000000001
--
-- Mật khẩu: password_hash là placeholder bắt đầu bằng '!' (không phải hash hợp lệ),
-- nên chưa ai đăng nhập được. Khi phân hệ A chốt thuật toán băm, cập nhật lại các dòng này.
--
-- id sinh tự động dùng md5('seed:<khóa>')::uuid để cố định giữa các lần chạy.

BEGIN;

-- ---------------------------------------------------------------- Tổ chức và chi nhánh
INSERT INTO organizations (id, name, slug) VALUES
    ('00000000-0000-4000-a000-000000000001', 'Basement', 'basement')
ON CONFLICT (id) DO NOTHING;

INSERT INTO branches (id, organization_id, code, name, address, capacity, opening_hours, late_fee_per_day, default_deposit_amount) VALUES
    ('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-a000-000000000001', 'HCM', 'Basement TP.HCM', 'TP. Hồ Chí Minh', 40,
     '{"open": "07:00", "close": "23:00"}', 5000, 100000),
    ('00000000-0000-4000-b000-000000000002', '00000000-0000-4000-a000-000000000001', 'DAD', 'Basement Đà Nẵng', 'Đà Nẵng', 30,
     '{"open": "07:00", "close": "23:00"}', 5000, 100000),
    ('00000000-0000-4000-b000-000000000003', '00000000-0000-4000-a000-000000000001', 'VCA', 'Basement Cần Thơ', 'Cần Thơ', 25,
     '{"open": "07:00", "close": "23:00"}', 5000, 100000)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------- Người dùng và vai trò
INSERT INTO users (id, organization_id, full_name, phone, email, password_hash, member_code, is_guest) VALUES
    ('00000000-0000-4000-c000-000000000001', '00000000-0000-4000-a000-000000000001', 'Chủ chuỗi Basement', NULL, 'owner@basement.local',   '!seed-chua-dat-mat-khau', 'BSM-0001', false),
    ('00000000-0000-4000-c000-000000000002', '00000000-0000-4000-a000-000000000001', 'Quản lý HCM',        NULL, 'manager.hcm@basement.local', '!seed-chua-dat-mat-khau', 'BSM-0002', false),
    ('00000000-0000-4000-c000-000000000003', '00000000-0000-4000-a000-000000000001', 'Nhân viên HCM',      NULL, 'staff.hcm@basement.local', '!seed-chua-dat-mat-khau', 'BSM-0003', false),
    ('00000000-0000-4000-c000-000000000004', '00000000-0000-4000-a000-000000000001', 'Nhân viên DAD',      NULL, 'staff.dad@basement.local', '!seed-chua-dat-mat-khau', 'BSM-0004', false),
    ('00000000-0000-4000-c000-000000000005', '00000000-0000-4000-a000-000000000001', 'Nhân viên VCA',      NULL, 'staff.vca@basement.local', '!seed-chua-dat-mat-khau', 'BSM-0005', false),
    ('00000000-0000-4000-c000-000000000011', '00000000-0000-4000-a000-000000000001', 'Khách hàng An',      '0900000011', 'khach.an@basement.local',   '!seed-chua-dat-mat-khau', 'BSM-0011', false),
    ('00000000-0000-4000-c000-000000000012', '00000000-0000-4000-a000-000000000001', 'Khách hàng Bảo',     '0900000012', 'khach.bao@basement.local',  '!seed-chua-dat-mat-khau', 'BSM-0012', false),
    ('00000000-0000-4000-c000-000000000013', '00000000-0000-4000-a000-000000000001', 'Khách hàng Chi',     '0900000013', NULL,                         '!seed-chua-dat-mat-khau', 'BSM-0013', false),
    ('00000000-0000-4000-c000-000000000021', '00000000-0000-4000-a000-000000000001', 'Khách vãng lai',     '0900000021', NULL,                         NULL,                      'BSM-0021', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_roles (id, organization_id, user_id, branch_id, role) VALUES
    (md5('seed:role:owner')::uuid,       '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-c000-000000000001', NULL,                                   'owner'),
    (md5('seed:role:manager-hcm')::uuid, '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-c000-000000000002', '00000000-0000-4000-b000-000000000001', 'branch_manager'),
    (md5('seed:role:staff-hcm')::uuid,   '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-c000-000000000003', '00000000-0000-4000-b000-000000000001', 'staff'),
    (md5('seed:role:staff-dad')::uuid,   '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-c000-000000000004', '00000000-0000-4000-b000-000000000002', 'staff'),
    (md5('seed:role:staff-vca')::uuid,   '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-c000-000000000005', '00000000-0000-4000-b000-000000000003', 'staff'),
    (md5('seed:role:cust-11')::uuid,     '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-c000-000000000011', NULL,                                   'customer'),
    (md5('seed:role:cust-12')::uuid,     '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-c000-000000000012', NULL,                                   'customer'),
    (md5('seed:role:cust-13')::uuid,     '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-c000-000000000013', NULL,                                   'customer')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------- Khung giờ và bảng giá
-- 2 khung mỗi ngày (vắng 07:00–17:00, đông 17:00–23:00) × 7 ngày × 3 chi nhánh.
INSERT INTO time_slots (id, organization_id, branch_id, name, day_of_week, start_time, end_time)
SELECT md5(format('seed:slot:%s:%s:%s', b.code, d, s.key))::uuid, b.organization_id, b.id, s.name, d, s.start_time, s.end_time
FROM branches b
CROSS JOIN generate_series(1, 7) AS d
CROSS JOIN (VALUES ('off', 'Giờ vắng', time '07:00', time '17:00'),
                   ('peak', 'Giờ đông', time '17:00', time '23:00')) AS s(key, name, start_time, end_time)
WHERE b.organization_id = '00000000-0000-4000-a000-000000000001' AND b.code IN ('HCM', 'DAD', 'VCA')
ON CONFLICT (id) DO NOTHING;

-- Đơn giá theo giờ (VND): vắng 10.000/15.000, đông 15.000/20.000 (không laptop/laptop).
INSERT INTO price_rules (id, organization_id, branch_id, time_slot_id, seating_type, price_per_hour)
SELECT md5(format('seed:price:%s:%s', t.id, p.seating))::uuid, t.organization_id, t.branch_id, t.id, p.seating::seating_type,
       CASE s.key WHEN 'off' THEN p.off_price ELSE p.peak_price END
FROM branches b
CROSS JOIN generate_series(1, 7) AS d
CROSS JOIN (VALUES ('off'), ('peak')) AS s(key)
JOIN time_slots t ON t.id = md5(format('seed:slot:%s:%s:%s', b.code, d, s.key))::uuid   -- chỉ khung giờ do seed tạo
CROSS JOIN (VALUES ('no_laptop', 10000, 15000), ('laptop', 15000, 20000)) AS p(seating, off_price, peak_price)
WHERE b.organization_id = '00000000-0000-4000-a000-000000000001'
ON CONFLICT (id) DO NOTHING;

INSERT INTO membership_plans (id, organization_id, name, seating_type, duration_days, price) VALUES
    (md5('seed:plan:no_laptop')::uuid, '00000000-0000-4000-a000-000000000001', 'Gói tháng không laptop', 'no_laptop', 30, 900000),
    (md5('seed:plan:laptop')::uuid,    '00000000-0000-4000-a000-000000000001', 'Gói tháng laptop',       'laptop',    30, 1200000)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------- Canteen
INSERT INTO products (id, organization_id, name, category, default_price) VALUES
    (md5('seed:product:caphe')::uuid,   '00000000-0000-4000-a000-000000000001', 'Cà phê sữa đá', 'drink', 25000),
    (md5('seed:product:tradao')::uuid,  '00000000-0000-4000-a000-000000000001', 'Trà đào',       'drink', 30000),
    (md5('seed:product:nuocsuoi')::uuid,'00000000-0000-4000-a000-000000000001', 'Nước suối',     'drink', 10000),
    (md5('seed:product:banhmi')::uuid,  '00000000-0000-4000-a000-000000000001', 'Bánh mì',       'food',  20000),
    (md5('seed:product:mily')::uuid,    '00000000-0000-4000-a000-000000000001', 'Mì ly',         'food',  15000)
ON CONFLICT (id) DO NOTHING;

-- Mọi sản phẩm bán ở mọi chi nhánh, tồn kho 50; giá NULL = dùng default_price.
INSERT INTO branch_products (id, organization_id, branch_id, product_id, price, stock_quantity)
SELECT md5(format('seed:bp:%s:%s', b.code, p.id))::uuid, b.organization_id, b.id, p.id, NULL, 50
FROM branches b JOIN products p ON p.organization_id = b.organization_id
WHERE b.organization_id = '00000000-0000-4000-a000-000000000001'
  AND p.id IN (md5('seed:product:caphe')::uuid, md5('seed:product:tradao')::uuid, md5('seed:product:nuocsuoi')::uuid,
               md5('seed:product:banhmi')::uuid, md5('seed:product:mily')::uuid)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------- Thư viện (vài đầu sách mẫu; kho 300–500 sách nạp riêng)
INSERT INTO books (id, organization_id, title, authors, language, description, categories) VALUES
    (md5('seed:book:1')::uuid, '00000000-0000-4000-a000-000000000001', 'Đắc Nhân Tâm', 'Dale Carnegie', 'vi',
     'Sách kỹ năng giao tiếp và ứng xử, hướng dẫn cách tạo thiện cảm và thuyết phục người khác.', '{"kỹ năng sống"}'),
    (md5('seed:book:2')::uuid, '00000000-0000-4000-a000-000000000001', 'Nhà Giả Kim', 'Paulo Coelho', 'vi',
     'Tiểu thuyết về hành trình theo đuổi ước mơ của chàng chăn cừu Santiago.', '{"tiểu thuyết"}'),
    (md5('seed:book:3')::uuid, '00000000-0000-4000-a000-000000000001', 'Tôi thấy hoa vàng trên cỏ xanh', 'Nguyễn Nhật Ánh', 'vi',
     'Truyện dài về tuổi thơ ở một làng quê miền Trung.', '{"văn học Việt Nam"}'),
    (md5('seed:book:4')::uuid, '00000000-0000-4000-a000-000000000001', 'Clean Code', 'Robert C. Martin', 'en',
     'A handbook of agile software craftsmanship: writing readable, maintainable code.', '{"programming"}'),
    (md5('seed:book:5')::uuid, '00000000-0000-4000-a000-000000000001', 'Sapiens: A Brief History of Humankind', 'Yuval Noah Harari', 'en',
     'An overview of human history from the Stone Age to the present.', '{"history"}'),
    (md5('seed:book:6')::uuid, '00000000-0000-4000-a000-000000000001', 'Atomic Habits', 'James Clear', 'en',
     'A practical guide to building good habits and breaking bad ones.', '{"self-help"}')
ON CONFLICT (id) DO NOTHING;

-- Bản sao: sách 1–3 có ở HCM và DAD, sách 4–6 có ở HCM và VCA.
INSERT INTO book_copies (id, organization_id, branch_id, book_id, barcode)
SELECT md5(format('seed:copy:%s:%s', c.branch_code, c.n))::uuid, '00000000-0000-4000-a000-000000000001', b.id,
       md5('seed:book:' || c.n)::uuid, format('%s-%s', c.branch_code, lpad(c.n::text, 4, '0'))
FROM (VALUES ('HCM', 1), ('HCM', 2), ('HCM', 3), ('HCM', 4), ('HCM', 5), ('HCM', 6),
             ('DAD', 1), ('DAD', 2), ('DAD', 3),
             ('VCA', 4), ('VCA', 5), ('VCA', 6)) AS c(branch_code, n)
JOIN branches b ON b.organization_id = '00000000-0000-4000-a000-000000000001' AND b.code = c.branch_code
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------- Phiên ngồi đang mở (để thấy chỗ trống thay đổi)
INSERT INTO seat_sessions (id, organization_id, branch_id, customer_id, seating_type, status, started_at, opened_by) VALUES
    (md5('seed:session:1')::uuid, '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-b000-000000000001',
     '00000000-0000-4000-c000-000000000011', 'laptop',    'active', now() - interval '2 hours',  '00000000-0000-4000-c000-000000000003'),
    (md5('seed:session:2')::uuid, '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-b000-000000000001',
     '00000000-0000-4000-c000-000000000012', 'no_laptop', 'active', now() - interval '45 minutes', '00000000-0000-4000-c000-000000000003'),
    (md5('seed:session:3')::uuid, '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-b000-000000000002',
     '00000000-0000-4000-c000-000000000021', 'no_laptop', 'active', now() - interval '30 minutes', '00000000-0000-4000-c000-000000000004')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------- Thông báo và bảng ý tưởng
INSERT INTO announcements (id, organization_id, branch_id, audience, title, body, is_pinned, created_by) VALUES
    (md5('seed:announcement:1')::uuid, '00000000-0000-4000-a000-000000000001', NULL, 'all',
     'Chào mừng đến với Basement', 'Hệ thống đang chạy thử. Mọi góp ý xin gửi cho nhân viên tại quầy.', true,
     '00000000-0000-4000-c000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO ideas (id, organization_id, branch_id, author_id, title, body) VALUES
    (md5('seed:idea:1')::uuid, '00000000-0000-4000-a000-000000000001', '00000000-0000-4000-b000-000000000001',
     '00000000-0000-4000-c000-000000000003', 'Thêm ổ cắm ở dãy bàn cạnh cửa sổ', 'Khách mang laptop hay hỏi chỗ cắm sạc ở khu này.')
ON CONFLICT (id) DO NOTHING;

COMMIT;
