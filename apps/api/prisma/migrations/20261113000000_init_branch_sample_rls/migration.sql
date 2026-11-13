-- CreateExtension
CREATE EXTENSION IF NOT EXISTS "vector";

-- CreateTable
CREATE TABLE IF NOT EXISTS "branch_samples" (
    "id" TEXT NOT NULL,
    "branch_code" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "branch_samples_pkey" PRIMARY KEY ("id")
);

-- Tạo application role nếu chưa tồn tại để đảm bảo tuân thủ Row-Level Security
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'basement_app') THEN
    CREATE ROLE basement_app WITH LOGIN PASSWORD 'basement_password' NOBYPASSRLS;
  END IF;
END
$$;

GRANT ALL ON SCHEMA public TO basement_app;
GRANT ALL ON ALL TABLES IN SCHEMA public TO basement_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO basement_app;

-- Bật Row-Level Security (RLS)
ALTER TABLE "branch_samples" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "branch_samples" FORCE ROW LEVEL SECURITY;

-- Tạo Policy lọc dữ liệu theo chi nhánh hiện tại
DROP POLICY IF EXISTS branch_isolation_policy ON "branch_samples";
CREATE POLICY branch_isolation_policy ON "branch_samples"
    FOR ALL
    USING ("branch_code" = current_setting('app.current_branch', true))
    WITH CHECK ("branch_code" = current_setting('app.current_branch', true));
