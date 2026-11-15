-- 1. Kích hoạt extension pgvector nếu chưa tồn tại
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Tạo role basement_app (NOLOGIN) nếu chưa tồn tại
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'basement_app') THEN CREATE ROLE basement_app NOLOGIN; END IF; END $$;

-- 3. Cấp quyền chuyển sang role basement_app cho user hiện tại của Neon (database owner)
GRANT basement_app TO CURRENT_USER;

-- 4. Cấp quyền USAGE trên schema public cho basement_app
GRANT USAGE ON SCHEMA public TO basement_app;

-- 5. Cấp quyền SELECT, INSERT, UPDATE, DELETE trên tất cả các bảng hiện tại trong schema public
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO basement_app;

-- 6. Cấp quyền mặc định SELECT, INSERT, UPDATE, DELETE trên các bảng tạo mới trong tương lai
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO basement_app;

-- 7. Cấp quyền USAGE, SELECT trên sequence (nếu có) để hỗ trợ các bảng dùng id tự tăng
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO basement_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO basement_app;
