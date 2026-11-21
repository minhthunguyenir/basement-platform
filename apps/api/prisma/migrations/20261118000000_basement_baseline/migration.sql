-- Baseline Basement: ghép nguyên văn docs/db/01_schema.sql + 02_triggers.sql + 03_rls.sql
-- (bỏ BEGIN;/COMMIT; của từng file). KHÔNG chứa 04_rls_tests.sql.
-- Nguồn chuẩn vẫn là docs/db; đổi lược đồ thì sửa docs/db rồi tạo migration mới.
-- Chạy bằng DIRECT_URL (owner/superuser): cần quyền tạo extension, role và đổi owner hàm.

-- ==================== docs/db/01_schema.sql ====================
-- 01_schema.sql — Basement: lược đồ cơ sở dữ liệu (25 bảng)
-- Yêu cầu: PostgreSQL 16+, pgvector 0.5+ (HNSW), btree_gist.
-- Nội dung: extension, enum, bảng, PK, UNIQUE, CHECK, FK, partial unique index, index.
-- Trigger updated_at: 02_triggers.sql. RLS và vai trò DB: 03_rls.sql.
-- Chạy bằng vai trò migration (chủ sở hữu schema), không chạy bằng vai trò ứng dụng.


-- ==========================================================================
-- Extension
-- ==========================================================================
CREATE EXTENSION IF NOT EXISTS btree_gist;  -- exclusion constraint trên uuid/smallint + range
CREATE EXTENSION IF NOT EXISTS vector;      -- pgvector: kiểu vector, vector_dims(), HNSW

-- ==========================================================================
-- Enum
-- ==========================================================================
CREATE TYPE user_role AS ENUM ('owner', 'branch_manager', 'staff', 'customer');
CREATE TYPE seating_type AS ENUM ('laptop', 'no_laptop');
CREATE TYPE session_status AS ENUM ('active', 'closed', 'void');
CREATE TYPE close_type AS ENUM ('normal', 'manual');
CREATE TYPE membership_status AS ENUM ('pending', 'active', 'cancelled');
CREATE TYPE product_category AS ENUM ('drink', 'food');
CREATE TYPE order_status AS ENUM ('open', 'confirmed', 'cancelled');
CREATE TYPE order_item_status AS ENUM ('active', 'void');
CREATE TYPE invoice_status AS ENUM ('unpaid', 'paid', 'cancelled');
CREATE TYPE payment_method AS ENUM ('cash', 'bank_transfer');
CREATE TYPE payment_status AS ENUM ('pending', 'confirmed', 'cancelled');
CREATE TYPE copy_status AS ENUM ('available', 'on_loan', 'lost', 'damaged');
CREATE TYPE loan_type AS ENUM ('in_place', 'take_home');
CREATE TYPE loan_status AS ENUM ('active', 'returned', 'lost', 'cancelled');
CREATE TYPE deposit_status AS ENUM ('held', 'refunded', 'forfeited');
CREATE TYPE search_mode AS ENUM ('fts', 'vector', 'hybrid');
CREATE TYPE announcement_audience AS ENUM ('customers', 'staff', 'all');
CREATE TYPE idea_status AS ENUM ('pending', 'reviewing', 'resolved', 'rejected');

-- ==========================================================================
-- Bảng — A. Nền tảng và phân quyền
-- ==========================================================================

-- organizations: Tổ chức (tenant) và tài khoản nhận tiền chung cho VietQR. Hiện vận hành 1 tổ chức, sẵn sàng cho SaaS.
CREATE TABLE organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name varchar(200) NOT NULL,
    slug varchar(50) NOT NULL,
    bank_bin varchar(10),
    bank_account_number varchar(30),
    bank_account_name varchar(100),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT chk_organizations_bank CHECK (num_nonnulls(bank_bin, bank_account_number, bank_account_name) IN (0, 3))
);
COMMENT ON TABLE organizations IS 'Tổ chức (tenant) và tài khoản nhận tiền chung cho VietQR. Hiện vận hành 1 tổ chức, sẵn sàng cho SaaS.';

-- branches: Chi nhánh: sức chứa, múi giờ, giờ mở cửa, phí trễ/ngày, cọc mặc định.
CREATE TABLE branches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    code varchar(20) NOT NULL,
    name varchar(200) NOT NULL,
    address text,
    timezone varchar(64) NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
    capacity integer NOT NULL,
    opening_hours jsonb,
    late_fee_per_day bigint NOT NULL DEFAULT 0,
    default_deposit_amount bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT uq_branches_id_org UNIQUE (id, organization_id),
    CONSTRAINT chk_branches_capacity CHECK (capacity > 0),
    CONSTRAINT chk_branches_money CHECK (late_fee_per_day >= 0 AND default_deposit_amount >= 0)
);
COMMENT ON TABLE branches IS 'Chi nhánh: sức chứa, múi giờ, giờ mở cửa, phí trễ/ngày, cọc mặc định.';

-- users: Mọi người dùng của tổ chức, gồm khách có tài khoản và khách vãng lai.
CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    full_name varchar(200),
    phone varchar(20),
    email varchar(255),
    password_hash text,
    member_code varchar(32) NOT NULL,
    is_guest boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT uq_users_id_org UNIQUE (id, organization_id),
    CONSTRAINT chk_users_guest CHECK (NOT is_guest OR (password_hash IS NULL AND (phone IS NOT NULL OR full_name IS NOT NULL))),
    CONSTRAINT chk_users_account CHECK (is_guest OR (full_name IS NOT NULL AND password_hash IS NOT NULL AND (email IS NOT NULL OR phone IS NOT NULL)))
);
COMMENT ON TABLE users IS 'Mọi người dùng của tổ chức, gồm khách có tài khoản và khách vãng lai.';

-- user_roles: Vai trò của người dùng theo chi nhánh hoặc toàn chuỗi.
CREATE TABLE user_roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    branch_id uuid,
    role user_role NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT chk_user_roles_chain_wide CHECK (role NOT IN ('owner', 'customer') OR branch_id IS NULL)
);
COMMENT ON TABLE user_roles IS 'Vai trò của người dùng theo chi nhánh hoặc toàn chuỗi.';

-- ==========================================================================
-- Bảng — B. Sức chứa và check-in
-- ==========================================================================

-- seat_sessions: Phiên ngồi do nhân viên mở và đóng tại quầy.
CREATE TABLE seat_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    seating_type seating_type NOT NULL,
    membership_id uuid,
    status session_status NOT NULL DEFAULT 'active',
    started_at timestamptz NOT NULL DEFAULT now(),
    ended_at timestamptz,
    closed_at timestamptz,
    close_type close_type,
    close_reason text,
    opened_by uuid NOT NULL,
    closed_by uuid,
    voided_by uuid,
    voided_at timestamptz,
    void_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_seat_sessions_id_branch UNIQUE (id, branch_id),
    CONSTRAINT chk_seat_sessions_active CHECK ((status = 'active') = (ended_at IS NULL)),
    CONSTRAINT chk_seat_sessions_order CHECK (ended_at IS NULL OR ended_at >= started_at),
    CONSTRAINT chk_seat_sessions_closed CHECK (status <> 'closed' OR (closed_at IS NOT NULL AND closed_by IS NOT NULL AND close_type IS NOT NULL AND ended_at <= closed_at)),
    CONSTRAINT chk_seat_sessions_normal_close CHECK (close_type IS DISTINCT FROM 'normal' OR ended_at = closed_at),
    CONSTRAINT chk_seat_sessions_manual_close CHECK (close_type IS DISTINCT FROM 'manual' OR close_reason IS NOT NULL),
    CONSTRAINT chk_seat_sessions_void CHECK (status <> 'void' OR (voided_by IS NOT NULL AND voided_at IS NOT NULL AND void_reason IS NOT NULL))
);
COMMENT ON TABLE seat_sessions IS 'Phiên ngồi do nhân viên mở và đóng tại quầy.';

-- ==========================================================================
-- Bảng — C. Giá và gói
-- ==========================================================================

-- time_slots: Khung giờ riêng của từng chi nhánh, theo ngày trong tuần.
CREATE TABLE time_slots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    name varchar(50) NOT NULL,
    day_of_week smallint NOT NULL,
    start_time time NOT NULL,
    end_time time NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT uq_time_slots_id_branch UNIQUE (id, branch_id),
    CONSTRAINT chk_time_slots_dow CHECK (day_of_week BETWEEN 1 AND 7),
    CONSTRAINT chk_time_slots_range CHECK (end_time > start_time)
);
COMMENT ON TABLE time_slots IS 'Khung giờ riêng của từng chi nhánh, theo ngày trong tuần.';

-- price_rules: Đơn giá theo giờ cho từng cặp khung giờ × hình thức ngồi.
CREATE TABLE price_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    time_slot_id uuid NOT NULL,
    seating_type seating_type NOT NULL,
    price_per_hour bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT chk_price_rules_price CHECK (price_per_hour >= 0)
);
COMMENT ON TABLE price_rules IS 'Đơn giá theo giờ cho từng cặp khung giờ × hình thức ngồi.';

-- membership_plans: Danh mục gói tháng, dùng được ở mọi chi nhánh, không giới hạn giờ.
CREATE TABLE membership_plans (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    name varchar(100) NOT NULL,
    seating_type seating_type NOT NULL,
    duration_days integer NOT NULL,
    price bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT uq_membership_plans_id_org UNIQUE (id, organization_id),
    CONSTRAINT chk_membership_plans_values CHECK (duration_days > 0 AND price >= 0)
);
COMMENT ON TABLE membership_plans IS 'Danh mục gói tháng, dùng được ở mọi chi nhánh, không giới hạn giờ.';

-- memberships: Gói khách đã mua; dùng ở mọi chi nhánh. Chi nhánh bán ghi trên hóa đơn.
CREATE TABLE memberships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    seating_type seating_type NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status membership_status NOT NULL DEFAULT 'pending',
    cancelled_by uuid,
    cancel_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_memberships_id_customer UNIQUE (id, customer_id),
    CONSTRAINT chk_memberships_dates CHECK (ends_on >= starts_on),
    CONSTRAINT chk_memberships_cancelled CHECK (status <> 'cancelled' OR (cancelled_by IS NOT NULL AND cancel_reason IS NOT NULL))
);
COMMENT ON TABLE memberships IS 'Gói khách đã mua; dùng ở mọi chi nhánh. Chi nhánh bán ghi trên hóa đơn.';

-- seat_session_segments: Các đoạn tính tiền của một phiên, tách theo khung giờ và nửa đêm.
CREATE TABLE seat_session_segments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    seat_session_id uuid NOT NULL,
    time_slot_id uuid NOT NULL,
    started_at timestamptz NOT NULL,
    ended_at timestamptz NOT NULL,
    price_per_hour bigint NOT NULL,
    amount bigint NOT NULL,
    is_covered_by_membership boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_segments_range CHECK (ended_at > started_at),
    CONSTRAINT chk_segments_amount CHECK (price_per_hour >= 0 AND amount >= 0),
    CONSTRAINT chk_segments_covered CHECK (NOT is_covered_by_membership OR amount = 0)
);
COMMENT ON TABLE seat_session_segments IS 'Các đoạn tính tiền của một phiên, tách theo khung giờ và nửa đêm.';

-- ==========================================================================
-- Bảng — D. Bán hàng và thanh toán
-- ==========================================================================

-- products: Sản phẩm đồ uống, đồ ăn (danh mục chung của tổ chức).
CREATE TABLE products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    name varchar(200) NOT NULL,
    category product_category NOT NULL,
    default_price bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT uq_products_id_org UNIQUE (id, organization_id),
    CONSTRAINT chk_products_price CHECK (default_price >= 0)
);
COMMENT ON TABLE products IS 'Sản phẩm đồ uống, đồ ăn (danh mục chung của tổ chức).';

-- branch_products: Sản phẩm bán tại chi nhánh: tồn kho và giá riêng.
CREATE TABLE branch_products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    product_id uuid NOT NULL,
    price bigint,
    stock_quantity integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT chk_branch_products_values CHECK (stock_quantity >= 0 AND (price IS NULL OR price >= 0))
);
COMMENT ON TABLE branch_products IS 'Sản phẩm bán tại chi nhánh: tồn kho và giá riêng.';

-- orders: Đơn canteen; gắn vào phiên ngồi hoặc là đơn lẻ.
CREATE TABLE orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    seat_session_id uuid,
    customer_id uuid,
    status order_status NOT NULL DEFAULT 'open',
    created_by uuid NOT NULL,
    cancelled_by uuid,
    cancel_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_orders_id_branch UNIQUE (id, branch_id),
    CONSTRAINT chk_orders_cancelled CHECK (status <> 'cancelled' OR (cancelled_by IS NOT NULL AND cancel_reason IS NOT NULL))
);
COMMENT ON TABLE orders IS 'Đơn canteen; gắn vào phiên ngồi hoặc là đơn lẻ.';

-- order_items: Chi tiết đơn với đơn giá chụp lại.
CREATE TABLE order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    order_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL,
    status order_item_status NOT NULL DEFAULT 'active',
    voided_by uuid,
    void_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_order_items_values CHECK (quantity > 0 AND unit_price >= 0),
    CONSTRAINT chk_order_items_void CHECK (status <> 'void' OR (voided_by IS NOT NULL AND void_reason IS NOT NULL))
);
COMMENT ON TABLE order_items IS 'Chi tiết đơn với đơn giá chụp lại.';

-- invoices: Hóa đơn cho đúng một trong ba: phiên ngồi, gói tháng, đơn lẻ.
CREATE TABLE invoices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    customer_id uuid,
    seat_session_id uuid,
    membership_id uuid,
    order_id uuid,
    code varchar(30) NOT NULL,
    seat_amount bigint NOT NULL DEFAULT 0,
    order_amount bigint NOT NULL DEFAULT 0,
    total_amount bigint NOT NULL,
    status invoice_status NOT NULL DEFAULT 'unpaid',
    paid_at timestamptz,
    created_by uuid NOT NULL,
    cancelled_by uuid,
    cancel_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_invoices_id_branch UNIQUE (id, branch_id),
    CONSTRAINT uq_invoices_code UNIQUE (organization_id, code),
    CONSTRAINT chk_invoices_one_target CHECK (num_nonnulls(seat_session_id, membership_id, order_id) = 1),
    CONSTRAINT chk_invoices_amounts CHECK (seat_amount >= 0 AND order_amount >= 0 AND total_amount >= 0),
    CONSTRAINT chk_invoices_seat_rounding CHECK (seat_amount % 1000 = 0),
    CONSTRAINT chk_invoices_seat_only_session CHECK (seat_session_id IS NOT NULL OR seat_amount = 0),
    CONSTRAINT chk_invoices_membership_amounts CHECK (membership_id IS NULL OR (seat_amount = 0 AND order_amount = 0)),
    CONSTRAINT chk_invoices_total CHECK (membership_id IS NOT NULL OR total_amount = seat_amount + order_amount),
    CONSTRAINT chk_invoices_customer CHECK ((seat_session_id IS NULL AND membership_id IS NULL) OR customer_id IS NOT NULL),
    CONSTRAINT chk_invoices_paid CHECK (status <> 'paid' OR paid_at IS NOT NULL),
    CONSTRAINT chk_invoices_cancelled CHECK (status <> 'cancelled' OR (cancelled_by IS NOT NULL AND cancel_reason IS NOT NULL))
);
COMMENT ON TABLE invoices IS 'Hóa đơn cho đúng một trong ba: phiên ngồi, gói tháng, đơn lẻ.';

-- payments: Một lần thu tiền mặt hoặc chuyển khoản; nhân viên xác nhận thủ công.
CREATE TABLE payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    method payment_method NOT NULL,
    amount bigint NOT NULL,
    status payment_status NOT NULL DEFAULT 'pending',
    transfer_reference varchar(30),
    created_by uuid NOT NULL,
    confirmed_by uuid,
    confirmed_at timestamptz,
    cancelled_by uuid,
    cancel_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_payments_amount CHECK (amount > 0),
    CONSTRAINT chk_payments_reference CHECK ((method = 'bank_transfer') = (transfer_reference IS NOT NULL)),
    CONSTRAINT chk_payments_confirmed CHECK (status <> 'confirmed' OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)),
    CONSTRAINT chk_payments_cancelled CHECK (status <> 'cancelled' OR (cancelled_by IS NOT NULL AND cancel_reason IS NOT NULL))
);
COMMENT ON TABLE payments IS 'Một lần thu tiền mặt hoặc chuyển khoản; nhân viên xác nhận thủ công.';

-- ==========================================================================
-- Bảng — E. Thư viện
-- ==========================================================================

-- books: Đầu sách (danh mục chung của tổ chức).
CREATE TABLE books (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    title varchar(500) NOT NULL,
    authors text,
    isbn varchar(20),
    language varchar(10) NOT NULL,
    description text,
    categories text[] NOT NULL DEFAULT '{}',
    search_vector tsvector GENERATED ALWAYS AS (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(authors, '') || ' ' || coalesce(description, ''))) STORED,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT uq_books_id_org UNIQUE (id, organization_id)
);
COMMENT ON TABLE books IS 'Đầu sách (danh mục chung của tổ chức).';

-- book_copies: Bản sao vật lý của một đầu sách, đặt tại một chi nhánh.
CREATE TABLE book_copies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    book_id uuid NOT NULL,
    barcode varchar(50) NOT NULL,
    status copy_status NOT NULL DEFAULT 'available',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT uq_book_copies_id_branch UNIQUE (id, branch_id)
);
COMMENT ON TABLE book_copies IS 'Bản sao vật lý của một đầu sách, đặt tại một chi nhánh.';

-- book_loans: Phiếu mượn một bản sao; tiền cọc và phí trễ ghi trên phiếu.
CREATE TABLE book_loans (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    book_copy_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    loan_type loan_type NOT NULL,
    seat_session_id uuid,
    status loan_status NOT NULL DEFAULT 'active',
    loaned_at timestamptz NOT NULL DEFAULT now(),
    due_at timestamptz NOT NULL,
    returned_at timestamptz,
    issued_by uuid NOT NULL,
    received_by uuid,
    deposit_amount bigint NOT NULL DEFAULT 0,
    deposit_method payment_method,
    deposit_status deposit_status,
    late_fee_amount bigint NOT NULL DEFAULT 0,
    cancel_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_book_loans_due CHECK (due_at > loaned_at),
    CONSTRAINT chk_book_loans_return_time CHECK (returned_at IS NULL OR returned_at >= loaned_at),
    CONSTRAINT chk_book_loans_session CHECK ((loan_type = 'in_place') = (seat_session_id IS NOT NULL)),
    CONSTRAINT chk_book_loans_returned CHECK (status <> 'returned' OR (returned_at IS NOT NULL AND received_by IS NOT NULL)),
    CONSTRAINT chk_book_loans_cancelled CHECK (status <> 'cancelled' OR cancel_reason IS NOT NULL),
    CONSTRAINT chk_book_loans_in_place_no_deposit CHECK (loan_type = 'take_home' OR deposit_amount = 0),
    CONSTRAINT chk_book_loans_deposit CHECK ((deposit_amount = 0 AND deposit_method IS NULL AND deposit_status IS NULL) OR (deposit_amount > 0 AND deposit_method IS NOT NULL AND deposit_status IS NOT NULL)),
    CONSTRAINT chk_book_loans_fee CHECK (late_fee_amount >= 0 AND late_fee_amount <= deposit_amount)
);
COMMENT ON TABLE book_loans IS 'Phiếu mượn một bản sao; tiền cọc và phí trễ ghi trên phiếu.';

-- ==========================================================================
-- Bảng — F. Tìm kiếm sách bằng AI
-- ==========================================================================

-- book_embeddings: Vector của mỗi đầu sách theo từng mô hình embedding.
CREATE TABLE book_embeddings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    book_id uuid NOT NULL,
    model_name varchar(100) NOT NULL,
    dimensions smallint NOT NULL,
    embedding vector NOT NULL,
    source_hash varchar(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_book_embeddings_model UNIQUE (book_id, model_name),
    CONSTRAINT chk_book_embeddings_dims CHECK (dimensions > 0 AND vector_dims(embedding) = dimensions)
);
COMMENT ON TABLE book_embeddings IS 'Vector của mỗi đầu sách theo từng mô hình embedding.';

-- book_search_logs: Nhật ký truy vấn tìm sách.
CREATE TABLE book_search_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid,
    user_id uuid,
    query_text text NOT NULL,
    language varchar(10),
    search_mode search_mode NOT NULL,
    model_name varchar(100),
    results jsonb NOT NULL DEFAULT '[]',
    latency_ms integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_search_logs_model CHECK ((search_mode = 'fts') = (model_name IS NULL)),
    CONSTRAINT chk_search_logs_latency CHECK (latency_ms >= 0)
);
COMMENT ON TABLE book_search_logs IS 'Nhật ký truy vấn tìm sách.';

-- ==========================================================================
-- Bảng — H. Thông báo
-- ==========================================================================

-- announcements: Thông báo theo đối tượng và phạm vi; lên lịch và ghim.
CREATE TABLE announcements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid,
    audience announcement_audience NOT NULL,
    title varchar(200) NOT NULL,
    body text NOT NULL,
    publish_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    is_pinned boolean NOT NULL DEFAULT false,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT uq_announcements_id_org UNIQUE (id, organization_id),
    CONSTRAINT chk_announcements_expiry CHECK (expires_at IS NULL OR expires_at > publish_at)
);
COMMENT ON TABLE announcements IS 'Thông báo theo đối tượng và phạm vi; lên lịch và ghim.';

-- announcement_reads: Xác nhận đã đọc: mỗi người một dòng cho mỗi thông báo.
CREATE TABLE announcement_reads (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    announcement_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_announcement_reads UNIQUE (announcement_id, user_id)
);
COMMENT ON TABLE announcement_reads IS 'Xác nhận đã đọc: mỗi người một dòng cho mỗi thông báo.';

-- ==========================================================================
-- Bảng — I. Bảng ý tưởng nhân viên
-- ==========================================================================

-- ideas: Bài ý tưởng của nhân viên; 4 trạng thái; xóa mềm bài vi phạm.
CREATE TABLE ideas (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    branch_id uuid,
    author_id uuid NOT NULL,
    title varchar(200) NOT NULL,
    body text NOT NULL,
    status idea_status NOT NULL DEFAULT 'pending',
    resolved_by uuid,
    resolved_at timestamptz,
    deleted_at timestamptz,
    deleted_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_ideas_id_org UNIQUE (id, organization_id),
    CONSTRAINT chk_ideas_resolved CHECK (status <> 'resolved' OR (resolved_by IS NOT NULL AND resolved_at IS NOT NULL)),
    CONSTRAINT chk_ideas_unresolved CHECK (status = 'resolved' OR (resolved_by IS NULL AND resolved_at IS NULL)),
    CONSTRAINT chk_ideas_deleted CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
COMMENT ON TABLE ideas IS 'Bài ý tưởng của nhân viên; 4 trạng thái; xóa mềm bài vi phạm.';

-- idea_comments: Bình luận dưới bài ý tưởng.
CREATE TABLE idea_comments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    idea_id uuid NOT NULL,
    author_id uuid NOT NULL,
    body text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
COMMENT ON TABLE idea_comments IS 'Bình luận dưới bài ý tưởng.';

-- ==========================================================================
-- Khóa ngoại (khóa kép kèm organization_id hoặc branch_id để cùng tổ chức, cùng chi nhánh)
-- ==========================================================================

-- branches
ALTER TABLE branches ADD CONSTRAINT fk_branches_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);

-- users
ALTER TABLE users ADD CONSTRAINT fk_users_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);

-- user_roles
ALTER TABLE user_roles ADD CONSTRAINT fk_user_roles_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE user_roles ADD CONSTRAINT fk_user_roles_user_id
    FOREIGN KEY (user_id, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE user_roles ADD CONSTRAINT fk_user_roles_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);

-- seat_sessions
ALTER TABLE seat_sessions ADD CONSTRAINT fk_seat_sessions_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE seat_sessions ADD CONSTRAINT fk_seat_sessions_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE seat_sessions ADD CONSTRAINT fk_seat_sessions_customer_id
    FOREIGN KEY (customer_id, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE seat_sessions ADD CONSTRAINT fk_seat_sessions_membership_id
    FOREIGN KEY (membership_id, customer_id) REFERENCES memberships (id, customer_id);
ALTER TABLE seat_sessions ADD CONSTRAINT fk_seat_sessions_opened_by
    FOREIGN KEY (opened_by, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE seat_sessions ADD CONSTRAINT fk_seat_sessions_closed_by
    FOREIGN KEY (closed_by, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE seat_sessions ADD CONSTRAINT fk_seat_sessions_voided_by
    FOREIGN KEY (voided_by, organization_id) REFERENCES users (id, organization_id);

-- time_slots
ALTER TABLE time_slots ADD CONSTRAINT fk_time_slots_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE time_slots ADD CONSTRAINT fk_time_slots_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);

-- price_rules
ALTER TABLE price_rules ADD CONSTRAINT fk_price_rules_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE price_rules ADD CONSTRAINT fk_price_rules_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE price_rules ADD CONSTRAINT fk_price_rules_time_slot_id
    FOREIGN KEY (time_slot_id, branch_id) REFERENCES time_slots (id, branch_id);

-- membership_plans
ALTER TABLE membership_plans ADD CONSTRAINT fk_membership_plans_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);

-- memberships
ALTER TABLE memberships ADD CONSTRAINT fk_memberships_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE memberships ADD CONSTRAINT fk_memberships_customer_id
    FOREIGN KEY (customer_id, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE memberships ADD CONSTRAINT fk_memberships_plan_id
    FOREIGN KEY (plan_id, organization_id) REFERENCES membership_plans (id, organization_id);
ALTER TABLE memberships ADD CONSTRAINT fk_memberships_cancelled_by
    FOREIGN KEY (cancelled_by, organization_id) REFERENCES users (id, organization_id);

-- seat_session_segments
ALTER TABLE seat_session_segments ADD CONSTRAINT fk_seat_session_segments_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE seat_session_segments ADD CONSTRAINT fk_seat_session_segments_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE seat_session_segments ADD CONSTRAINT fk_seat_session_segments_seat_session_id
    FOREIGN KEY (seat_session_id, branch_id) REFERENCES seat_sessions (id, branch_id);
ALTER TABLE seat_session_segments ADD CONSTRAINT fk_seat_session_segments_time_slot_id
    FOREIGN KEY (time_slot_id, branch_id) REFERENCES time_slots (id, branch_id);

-- products
ALTER TABLE products ADD CONSTRAINT fk_products_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);

-- branch_products
ALTER TABLE branch_products ADD CONSTRAINT fk_branch_products_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE branch_products ADD CONSTRAINT fk_branch_products_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE branch_products ADD CONSTRAINT fk_branch_products_product_id
    FOREIGN KEY (product_id, organization_id) REFERENCES products (id, organization_id);

-- orders
ALTER TABLE orders ADD CONSTRAINT fk_orders_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE orders ADD CONSTRAINT fk_orders_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE orders ADD CONSTRAINT fk_orders_seat_session_id
    FOREIGN KEY (seat_session_id, branch_id) REFERENCES seat_sessions (id, branch_id);
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer_id
    FOREIGN KEY (customer_id, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE orders ADD CONSTRAINT fk_orders_created_by
    FOREIGN KEY (created_by, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE orders ADD CONSTRAINT fk_orders_cancelled_by
    FOREIGN KEY (cancelled_by, organization_id) REFERENCES users (id, organization_id);

-- order_items
ALTER TABLE order_items ADD CONSTRAINT fk_order_items_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE order_items ADD CONSTRAINT fk_order_items_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE order_items ADD CONSTRAINT fk_order_items_order_id
    FOREIGN KEY (order_id, branch_id) REFERENCES orders (id, branch_id);
ALTER TABLE order_items ADD CONSTRAINT fk_order_items_product_id
    FOREIGN KEY (product_id, organization_id) REFERENCES products (id, organization_id);
ALTER TABLE order_items ADD CONSTRAINT fk_order_items_voided_by
    FOREIGN KEY (voided_by, organization_id) REFERENCES users (id, organization_id);

-- invoices
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_customer_id
    FOREIGN KEY (customer_id, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_seat_session_id
    FOREIGN KEY (seat_session_id, branch_id) REFERENCES seat_sessions (id, branch_id);
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_membership_id
    FOREIGN KEY (membership_id, customer_id) REFERENCES memberships (id, customer_id);
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_order_id
    FOREIGN KEY (order_id, branch_id) REFERENCES orders (id, branch_id);
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_created_by
    FOREIGN KEY (created_by, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_cancelled_by
    FOREIGN KEY (cancelled_by, organization_id) REFERENCES users (id, organization_id);

-- payments
ALTER TABLE payments ADD CONSTRAINT fk_payments_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE payments ADD CONSTRAINT fk_payments_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE payments ADD CONSTRAINT fk_payments_invoice_id
    FOREIGN KEY (invoice_id, branch_id) REFERENCES invoices (id, branch_id);
ALTER TABLE payments ADD CONSTRAINT fk_payments_created_by
    FOREIGN KEY (created_by, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE payments ADD CONSTRAINT fk_payments_confirmed_by
    FOREIGN KEY (confirmed_by, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE payments ADD CONSTRAINT fk_payments_cancelled_by
    FOREIGN KEY (cancelled_by, organization_id) REFERENCES users (id, organization_id);

-- books
ALTER TABLE books ADD CONSTRAINT fk_books_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);

-- book_copies
ALTER TABLE book_copies ADD CONSTRAINT fk_book_copies_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE book_copies ADD CONSTRAINT fk_book_copies_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE book_copies ADD CONSTRAINT fk_book_copies_book_id
    FOREIGN KEY (book_id, organization_id) REFERENCES books (id, organization_id);

-- book_loans
ALTER TABLE book_loans ADD CONSTRAINT fk_book_loans_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE book_loans ADD CONSTRAINT fk_book_loans_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE book_loans ADD CONSTRAINT fk_book_loans_book_copy_id
    FOREIGN KEY (book_copy_id, branch_id) REFERENCES book_copies (id, branch_id);
ALTER TABLE book_loans ADD CONSTRAINT fk_book_loans_customer_id
    FOREIGN KEY (customer_id, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE book_loans ADD CONSTRAINT fk_book_loans_seat_session_id
    FOREIGN KEY (seat_session_id, branch_id) REFERENCES seat_sessions (id, branch_id);
ALTER TABLE book_loans ADD CONSTRAINT fk_book_loans_issued_by
    FOREIGN KEY (issued_by, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE book_loans ADD CONSTRAINT fk_book_loans_received_by
    FOREIGN KEY (received_by, organization_id) REFERENCES users (id, organization_id);

-- book_embeddings
ALTER TABLE book_embeddings ADD CONSTRAINT fk_book_embeddings_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE book_embeddings ADD CONSTRAINT fk_book_embeddings_book_id
    FOREIGN KEY (book_id, organization_id) REFERENCES books (id, organization_id);

-- book_search_logs
ALTER TABLE book_search_logs ADD CONSTRAINT fk_book_search_logs_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE book_search_logs ADD CONSTRAINT fk_book_search_logs_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE book_search_logs ADD CONSTRAINT fk_book_search_logs_user_id
    FOREIGN KEY (user_id, organization_id) REFERENCES users (id, organization_id);

-- announcements
ALTER TABLE announcements ADD CONSTRAINT fk_announcements_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE announcements ADD CONSTRAINT fk_announcements_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE announcements ADD CONSTRAINT fk_announcements_created_by
    FOREIGN KEY (created_by, organization_id) REFERENCES users (id, organization_id);

-- announcement_reads
ALTER TABLE announcement_reads ADD CONSTRAINT fk_announcement_reads_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE announcement_reads ADD CONSTRAINT fk_announcement_reads_announcement_id
    FOREIGN KEY (announcement_id, organization_id) REFERENCES announcements (id, organization_id);
ALTER TABLE announcement_reads ADD CONSTRAINT fk_announcement_reads_user_id
    FOREIGN KEY (user_id, organization_id) REFERENCES users (id, organization_id);

-- ideas
ALTER TABLE ideas ADD CONSTRAINT fk_ideas_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE ideas ADD CONSTRAINT fk_ideas_branch_id
    FOREIGN KEY (branch_id, organization_id) REFERENCES branches (id, organization_id);
ALTER TABLE ideas ADD CONSTRAINT fk_ideas_author_id
    FOREIGN KEY (author_id, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE ideas ADD CONSTRAINT fk_ideas_resolved_by
    FOREIGN KEY (resolved_by, organization_id) REFERENCES users (id, organization_id);
ALTER TABLE ideas ADD CONSTRAINT fk_ideas_deleted_by
    FOREIGN KEY (deleted_by, organization_id) REFERENCES users (id, organization_id);

-- idea_comments
ALTER TABLE idea_comments ADD CONSTRAINT fk_idea_comments_organization_id
    FOREIGN KEY (organization_id) REFERENCES organizations (id);
ALTER TABLE idea_comments ADD CONSTRAINT fk_idea_comments_idea_id
    FOREIGN KEY (idea_id, organization_id) REFERENCES ideas (id, organization_id);
ALTER TABLE idea_comments ADD CONSTRAINT fk_idea_comments_author_id
    FOREIGN KEY (author_id, organization_id) REFERENCES users (id, organization_id);

-- ==========================================================================
-- Partial unique index, exclusion constraint và index cho truy vấn thường dùng
-- ==========================================================================

-- organizations
-- slug duy nhất trong các tổ chức chưa xóa
CREATE UNIQUE INDEX uq_organizations_slug ON organizations (lower(slug)) WHERE deleted_at IS NULL;

-- branches
-- mã chi nhánh duy nhất trong tổ chức (chi nhánh chưa xóa)
CREATE UNIQUE INDEX uq_branches_code ON branches (organization_id, code) WHERE deleted_at IS NULL;

-- users
-- mã thành viên duy nhất trong tổ chức
CREATE UNIQUE INDEX uq_users_member_code ON users (organization_id, member_code) WHERE deleted_at IS NULL;
-- email duy nhất trong tổ chức (không phân biệt hoa thường)
CREATE UNIQUE INDEX uq_users_email ON users (organization_id, lower(email)) WHERE deleted_at IS NULL AND email IS NOT NULL;
-- số điện thoại duy nhất trong tổ chức, áp dụng chung cho khách vãng lai và tài khoản thật
CREATE UNIQUE INDEX uq_users_phone ON users (organization_id, phone) WHERE deleted_at IS NULL AND phone IS NOT NULL;

-- user_roles
-- không gán trùng một vai trò ở cùng phạm vi (NULLS NOT DISTINCT, PostgreSQL 15+)
CREATE UNIQUE INDEX uq_user_roles ON user_roles (user_id, role, branch_id) NULLS NOT DISTINCT WHERE deleted_at IS NULL;

-- seat_sessions
-- mỗi khách chỉ có một phiên active trong toàn tổ chức
CREATE UNIQUE INDEX uq_seat_sessions_one_active ON seat_sessions (organization_id, customer_id) WHERE status = 'active';
-- đếm số phiên đang mở để tính chỗ trống
CREATE INDEX ix_seat_sessions_active_branch ON seat_sessions (branch_id) WHERE status = 'active';

-- time_slots
-- exclusion constraint: các khung của một chi nhánh không chồng nhau trong cùng ngày (cần btree_gist)
ALTER TABLE time_slots ADD CONSTRAINT ex_time_slots_no_overlap
    EXCLUDE USING gist (branch_id WITH =, day_of_week WITH =, int4range(EXTRACT(EPOCH FROM start_time)::int, EXTRACT(EPOCH FROM end_time)::int) WITH &&)
    WHERE (deleted_at IS NULL);

-- price_rules
-- mỗi khung có đúng một giá cho mỗi hình thức ngồi
CREATE UNIQUE INDEX uq_price_rules ON price_rules (time_slot_id, seating_type) WHERE deleted_at IS NULL;

-- membership_plans
-- tên gói duy nhất trong tổ chức
CREATE UNIQUE INDEX uq_membership_plans_name ON membership_plans (organization_id, name) WHERE deleted_at IS NULL;

-- memberships
-- tìm gói còn hiệu lực khi mở phiên
CREATE INDEX ix_memberships_active ON memberships (customer_id, ends_on) WHERE status = 'active';

-- seat_session_segments
-- exclusion constraint: các đoạn của cùng một phiên không chồng nhau
ALTER TABLE seat_session_segments ADD CONSTRAINT ex_segments_no_overlap
    EXCLUDE USING gist (seat_session_id WITH =, tstzrange(started_at, ended_at) WITH &&);
-- báo cáo công suất theo khung giờ
CREATE INDEX ix_segments_time_slot ON seat_session_segments (time_slot_id);

-- products
-- tên sản phẩm duy nhất trong tổ chức
CREATE UNIQUE INDEX uq_products_name ON products (organization_id, name) WHERE deleted_at IS NULL;

-- branch_products
-- mỗi sản phẩm một dòng tồn kho tại mỗi chi nhánh
CREATE UNIQUE INDEX uq_branch_products ON branch_products (branch_id, product_id) WHERE deleted_at IS NULL;

-- orders
-- gom đơn của một phiên khi lập hóa đơn
CREATE INDEX ix_orders_session ON orders (seat_session_id) WHERE seat_session_id IS NOT NULL;

-- order_items
-- lấy chi tiết đơn khi tính tổng hóa đơn
CREATE INDEX ix_order_items_order ON order_items (order_id);

-- invoices
-- mỗi phiên có nhiều nhất một hóa đơn còn hiệu lực
CREATE UNIQUE INDEX uq_invoices_session ON invoices (seat_session_id) WHERE status <> 'cancelled';
-- mỗi gói có nhiều nhất một hóa đơn còn hiệu lực
CREATE UNIQUE INDEX uq_invoices_membership ON invoices (membership_id) WHERE status <> 'cancelled';
-- mỗi đơn lẻ có nhiều nhất một hóa đơn còn hiệu lực
CREATE UNIQUE INDEX uq_invoices_order ON invoices (order_id) WHERE status <> 'cancelled';
-- danh sách hóa đơn chưa thanh toán của chi nhánh
CREATE INDEX ix_invoices_open ON invoices (branch_id, created_at) WHERE status = 'unpaid';

-- payments
-- nội dung chuyển khoản duy nhất trong tổ chức
CREATE UNIQUE INDEX uq_payments_reference ON payments (organization_id, transfer_reference) WHERE transfer_reference IS NOT NULL;
-- mỗi hóa đơn có nhiều nhất một thanh toán confirmed (không trả nhiều lần)
CREATE UNIQUE INDEX uq_payments_one_confirmed ON payments (invoice_id) WHERE status = 'confirmed';
-- lấy các lần thu của một hóa đơn, kể cả lần đã hủy
CREATE INDEX ix_payments_invoice ON payments (invoice_id);

-- books
-- ISBN duy nhất trong tổ chức
CREATE UNIQUE INDEX uq_books_isbn ON books (organization_id, isbn) WHERE isbn IS NOT NULL AND deleted_at IS NULL;
-- GIN index cho tìm toàn văn
CREATE INDEX ix_books_search ON books USING gin (search_vector);

-- book_copies
-- mã vạch duy nhất trong tổ chức
CREATE UNIQUE INDEX uq_book_copies_barcode ON book_copies (organization_id, barcode) WHERE deleted_at IS NULL;
-- lọc sách còn tại chi nhánh khi tìm kiếm
CREATE INDEX ix_book_copies_available ON book_copies (book_id, branch_id) WHERE status = 'available' AND deleted_at IS NULL;

-- book_loans
-- mỗi bản sao chỉ có một phiếu đang mượn
CREATE UNIQUE INDEX uq_book_loans_active_copy ON book_loans (book_copy_id) WHERE status = 'active';
-- sách khách đang giữ
CREATE INDEX ix_book_loans_customer ON book_loans (customer_id) WHERE status = 'active';

-- book_search_logs
-- báo cáo sách được tìm nhiều theo thời gian
CREATE INDEX ix_search_logs_time ON book_search_logs (organization_id, created_at);

-- announcements
-- thông báo theo phạm vi (branch_id NULL hoặc chi nhánh của người xem) và thời điểm đăng
CREATE INDEX ix_announcements_feed ON announcements (organization_id, branch_id, publish_at) WHERE deleted_at IS NULL;

-- ideas
-- danh sách bài chưa xóa, lọc theo trạng thái
CREATE INDEX ix_ideas_list ON ideas (organization_id, status, created_at) WHERE deleted_at IS NULL;

-- idea_comments
-- bình luận chưa xóa của một bài
CREATE INDEX ix_idea_comments_idea ON idea_comments (idea_id, created_at) WHERE deleted_at IS NULL;

-- ==========================================================================
-- Vector index (pgvector HNSW) — mỗi mô hình embedding một index một phần
-- ==========================================================================
-- Tạo sau khi chốt tên và số chiều của từng mô hình; ví dụ cho mô hình 768 chiều:
-- CREATE INDEX ix_book_embeddings_hnsw_<model>
--     ON book_embeddings USING hnsw ((embedding::vector(768)) vector_cosine_ops)
--     WHERE model_name = '<tên mô hình>';
-- Truy vấn phải dùng đúng biểu thức để index được chọn:
--   ORDER BY embedding::vector(768) <=> $1::vector(768) ... WHERE model_name = '<tên mô hình>'


-- Giả định
-- 1. Chạy bằng vai trò migration sở hữu schema public; vai trò ứng dụng và RLS khai báo ở 03_rls.sql.
-- 2. Mọi FK dùng NO ACTION (không xóa dây chuyền) vì dữ liệu được xóa mềm hoặc hủy bằng trạng thái.
-- 3. Tìm toàn văn dùng cấu hình 'simple' (PostgreSQL không có từ điển tiếng Việt), giữ nguyên dấu.
-- 4. Quy tắc liên bảng (amount = total khi xác nhận, chỉ void khi chưa thu tiền, trừ tồn kho…) do service xử lý.
-- 5. HNSW index tạo khi đã chốt mô hình; trước đó tìm vector vẫn chạy được nhưng quét tuần tự.

-- ==================== docs/db/02_triggers.sql ====================
-- 02_triggers.sql — Basement: tự cập nhật updated_at
-- Chạy sau 01_schema.sql, bằng vai trò migration.
-- Gắn vào 22 bảng có updated_at. Bỏ qua 3 bảng chỉ ghi thêm: seat_session_segments, book_search_logs, announcement_reads.


CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    -- Dùng clock_timestamp() để nhiều UPDATE trong cùng giao dịch vẫn có mốc tăng dần;
    -- created_at dùng now() (đầu giao dịch) nên updated_at luôn >= created_at.
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
END $$;

COMMENT ON FUNCTION set_updated_at() IS 'Gán updated_at mỗi khi một dòng được UPDATE.';

CREATE TRIGGER trg_organizations_updated_at
    BEFORE UPDATE ON organizations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_branches_updated_at
    BEFORE UPDATE ON branches
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_user_roles_updated_at
    BEFORE UPDATE ON user_roles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_seat_sessions_updated_at
    BEFORE UPDATE ON seat_sessions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_time_slots_updated_at
    BEFORE UPDATE ON time_slots
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_price_rules_updated_at
    BEFORE UPDATE ON price_rules
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_membership_plans_updated_at
    BEFORE UPDATE ON membership_plans
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_memberships_updated_at
    BEFORE UPDATE ON memberships
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_branch_products_updated_at
    BEFORE UPDATE ON branch_products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_order_items_updated_at
    BEFORE UPDATE ON order_items
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_invoices_updated_at
    BEFORE UPDATE ON invoices
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_books_updated_at
    BEFORE UPDATE ON books
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_book_copies_updated_at
    BEFORE UPDATE ON book_copies
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_book_loans_updated_at
    BEFORE UPDATE ON book_loans
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_book_embeddings_updated_at
    BEFORE UPDATE ON book_embeddings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_announcements_updated_at
    BEFORE UPDATE ON announcements
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_ideas_updated_at
    BEFORE UPDATE ON ideas
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_idea_comments_updated_at
    BEFORE UPDATE ON idea_comments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- Giả định
-- 1. Ứng dụng không tự gửi updated_at; nếu có gửi, trigger vẫn ghi đè bằng giờ máy chủ.
-- 2. Trigger chạy cả khi UPDATE không đổi giá trị nào (PostgreSQL không tự bỏ qua); service tránh UPDATE thừa.
-- 3. Không thêm trigger nghiệp vụ (đổi trạng thái hóa đơn, trừ tồn kho, cập nhật book_copies.status): service xử lý trong cùng giao dịch.
-- 4. Hàm nằm ở schema public, chủ sở hữu là vai trò migration; vai trò ứng dụng không cần quyền gì thêm để trigger chạy.

-- ==================== docs/db/03_rls.sql ====================
-- 03_rls.sql — Basement: vai trò DB, hàm hỗ trợ và Row-Level Security
-- Chạy sau 01_schema.sql và 02_triggers.sql, bằng tài khoản quản trị có quyền CREATEROLE
-- và BYPASSRLS (vd. superuser của môi trường tự cài, hoặc vai trò admin của dịch vụ cloud).
--
-- Ba vai trò DB:
--   * basement_owner    : vai trò migration, sở hữu bảng (đã dùng để chạy 01, 02).
--                         Bảng bật FORCE RLS nên chính owner cũng bị RLS lọc khi truy cập dữ liệu.
--   * basement_security : NOLOGIN, BYPASSRLS. Chỉ sở hữu các hàm SECURITY DEFINER bên dưới,
--                         để hàm đọc được user_roles mà không gọi đệ quy RLS.
--   * basement_app      : vai trò ứng dụng NestJS. LOGIN, không superuser, không sở hữu bảng,
--                         NOBYPASSRLS. Mọi truy cập dữ liệu đi qua vai trò này.
--
-- Mỗi giao dịch, ứng dụng gán ngữ cảnh (SET LOCAL hoặc set_config(..., true)):
--   SELECT set_config('app.organization_id', '<uuid tổ chức>', true),
--          set_config('app.user_id',         '<uuid người dùng hoặc rỗng>', true);
-- Thiếu app.organization_id thì mọi bảng trả 0 dòng (đóng mặc định).


-- ===========================================================================
-- 1. Vai trò
-- ===========================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'basement_security') THEN
        CREATE ROLE basement_security NOLOGIN BYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'basement_app') THEN
        -- Đặt mật khẩu ngoài file này: ALTER ROLE basement_app PASSWORD '...';
        CREATE ROLE basement_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOINHERIT;
    END IF;
END $$;

-- Vai trò có thể đã tồn tại từ trước với thuộc tính khác (vai trò thuộc cả cụm, không riêng
-- database; vd. còn sót từ bản prototype). Chuẩn hóa lại để luôn đúng thiết kế.
-- Không đụng SUPERUSER (chỉ superuser mới đổi được) và PASSWORD (đặt ngoài file này).
ALTER ROLE basement_security NOLOGIN BYPASSRLS;
ALTER ROLE basement_app LOGIN NOCREATEDB NOCREATEROLE NOBYPASSRLS NOINHERIT;

-- Cho vai trò đang chạy file này quyền SET ROLE sang hai vai trò trên. Bắt buộc khi chạy bằng
-- owner không phải superuser (vd. neondb_owner trên Neon): ALTER FUNCTION ... OWNER TO ở mục 4
-- đòi quyền này, và 04_rls_tests.sql dùng SET ROLE basement_app. Với superuser thì vô hại.
GRANT basement_security TO CURRENT_USER;
GRANT basement_app TO CURRENT_USER;

CREATE SCHEMA IF NOT EXISTS app;
REVOKE ALL ON SCHEMA app FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO basement_app, basement_security;
GRANT USAGE ON SCHEMA public TO basement_app, basement_security;

-- ===========================================================================
-- 2. Hàm đọc ngữ cảnh phiên
-- ===========================================================================
CREATE OR REPLACE FUNCTION app.org_id() RETURNS uuid
    LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('app.organization_id', true), '')::uuid $$;

CREATE OR REPLACE FUNCTION app.user_id() RETURNS uuid
    LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('app.user_id', true), '')::uuid $$;

-- ===========================================================================
-- 3. Hàm kiểm tra vai trò (SECURITY DEFINER, sở hữu bởi basement_security)
--    Vai trò toàn chuỗi (user_roles.branch_id IS NULL) có quyền ở mọi chi nhánh.
-- ===========================================================================
CREATE OR REPLACE FUNCTION app.is_staff() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (SELECT 1 FROM user_roles r
                   WHERE r.organization_id = app.org_id() AND r.user_id = app.user_id()
                     AND r.deleted_at IS NULL AND r.role IN ('owner', 'branch_manager', 'staff'))
$$;

CREATE OR REPLACE FUNCTION app.is_manager() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (SELECT 1 FROM user_roles r
                   WHERE r.organization_id = app.org_id() AND r.user_id = app.user_id()
                     AND r.deleted_at IS NULL AND r.role IN ('owner', 'branch_manager'))
$$;

CREATE OR REPLACE FUNCTION app.is_owner() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (SELECT 1 FROM user_roles r
                   WHERE r.organization_id = app.org_id() AND r.user_id = app.user_id()
                     AND r.deleted_at IS NULL AND r.role = 'owner')
$$;

-- Nhân viên, quản lý hoặc chủ có quyền ở chi nhánh p_branch (hoặc có vai trò toàn chuỗi).
CREATE OR REPLACE FUNCTION app.can_access_branch(p_branch uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (SELECT 1 FROM user_roles r
                   WHERE r.organization_id = app.org_id() AND r.user_id = app.user_id()
                     AND r.deleted_at IS NULL AND r.role IN ('owner', 'branch_manager', 'staff')
                     AND (r.branch_id IS NULL OR r.branch_id = p_branch))
$$;

-- Quản lý của chi nhánh p_branch, hoặc chủ/quản lý toàn chuỗi.
-- p_branch NULL (dữ liệu toàn chuỗi): chỉ vai trò toàn chuỗi mới quản lý được.
CREATE OR REPLACE FUNCTION app.can_manage_branch(p_branch uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (SELECT 1 FROM user_roles r
                   WHERE r.organization_id = app.org_id() AND r.user_id = app.user_id()
                     AND r.deleted_at IS NULL AND r.role IN ('owner', 'branch_manager')
                     AND (r.branch_id IS NULL OR r.branch_id = p_branch))
$$;

-- ===========================================================================
-- 4. Hàm nghiệp vụ cần đọc vượt RLS (SECURITY DEFINER, tự lọc theo tổ chức)
-- ===========================================================================
-- Số chỗ trống từng chi nhánh: ai cũng gọi được, kể cả khách chưa đăng nhập.
-- Chỉ trả con số, không lộ phiên ngồi của ai.
CREATE OR REPLACE FUNCTION app.branch_occupancy()
    RETURNS TABLE (branch_id uuid, branch_name varchar, capacity integer, active_sessions integer, free_seats integer)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
    SELECT b.id, b.name, b.capacity, count(s.id)::integer, (b.capacity - count(s.id))::integer
    FROM branches b
    LEFT JOIN seat_sessions s ON s.branch_id = b.id AND s.status = 'active'
    WHERE b.organization_id = app.org_id() AND b.deleted_at IS NULL
    GROUP BY b.id, b.name, b.capacity
    ORDER BY b.name
$$;

-- Khách đang có phiên mở ở chi nhánh nào: cho nhân viên chi nhánh khác biết vì sao
-- không mở được phiên mới (uq_seat_sessions_one_active), mà không cho đọc cả phiên.
CREATE OR REPLACE FUNCTION app.customer_active_session(p_customer uuid)
    RETURNS TABLE (branch_id uuid, started_at timestamptz)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
    SELECT s.branch_id, s.started_at
    FROM seat_sessions s
    WHERE app.is_staff() AND s.organization_id = app.org_id()
      AND s.customer_id = p_customer AND s.status = 'active'
$$;

-- Đăng nhập: vai trò ứng dụng không được SELECT users.password_hash; lấy qua hàm này.
CREATE OR REPLACE FUNCTION app.login_lookup(p_login text)
    RETURNS TABLE (user_id uuid, password_hash text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
    SELECT u.id, u.password_hash
    FROM users u
    WHERE u.organization_id = app.org_id() AND u.deleted_at IS NULL AND NOT u.is_guest
      AND (lower(u.email) = lower(p_login) OR u.phone = p_login)
$$;

-- Khách tự đăng ký (chưa có app.user_id). Trùng số điện thoại với khách vãng lai
-- thì nâng cấp chính dòng đó; luôn bảo đảm có vai trò customer.
CREATE OR REPLACE FUNCTION app.register_customer(p_full_name varchar, p_phone varchar, p_email varchar,
                                                 p_password_hash text, p_member_code varchar)
    RETURNS uuid
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
    v_org uuid := app.org_id();
    v_id  uuid;
BEGIN
    IF v_org IS NULL THEN
        RAISE EXCEPTION 'app.organization_id chưa được gán';
    END IF;
    UPDATE users SET full_name = p_full_name, email = p_email, password_hash = p_password_hash, is_guest = false
     WHERE organization_id = v_org AND phone = p_phone AND is_guest AND deleted_at IS NULL
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN
        INSERT INTO users (organization_id, full_name, phone, email, password_hash, member_code, is_guest)
        VALUES (v_org, p_full_name, p_phone, p_email, p_password_hash, p_member_code, false)
        RETURNING id INTO v_id;
    END IF;
    INSERT INTO user_roles (organization_id, user_id, branch_id, role)
    SELECT v_org, v_id, NULL, 'customer'
    WHERE NOT EXISTS (SELECT 1 FROM user_roles r WHERE r.user_id = v_id AND r.role = 'customer'
                      AND r.branch_id IS NULL AND r.deleted_at IS NULL);
    RETURN v_id;
END $$;

-- Quyền cho chủ sở hữu hàm và cho vai trò ứng dụng
GRANT SELECT ON user_roles, branches, seat_sessions TO basement_security;
GRANT SELECT, INSERT, UPDATE ON users TO basement_security;
GRANT INSERT ON user_roles TO basement_security;

-- ALTER FUNCTION ... OWNER TO đòi chủ mới có quyền CREATE trên schema chứa hàm (superuser được
-- miễn kiểm tra này, owner thường thì không). Cấp tạm rồi thu hồi ngay sau khi đổi chủ.
GRANT CREATE ON SCHEMA app TO basement_security;

ALTER FUNCTION app.is_staff()                     OWNER TO basement_security;
ALTER FUNCTION app.is_manager()                   OWNER TO basement_security;
ALTER FUNCTION app.is_owner()                     OWNER TO basement_security;
ALTER FUNCTION app.can_access_branch(uuid)        OWNER TO basement_security;
ALTER FUNCTION app.can_manage_branch(uuid)        OWNER TO basement_security;
ALTER FUNCTION app.branch_occupancy()             OWNER TO basement_security;
ALTER FUNCTION app.customer_active_session(uuid)  OWNER TO basement_security;
ALTER FUNCTION app.login_lookup(text)             OWNER TO basement_security;
ALTER FUNCTION app.register_customer(varchar, varchar, varchar, text, varchar) OWNER TO basement_security;

REVOKE CREATE ON SCHEMA app FROM basement_security;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO basement_app;
-- Các hàm SECURITY DEFINER chạy dưới quyền basement_security và gọi lại app.org_id(), app.user_id(), app.is_staff().
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO basement_security;

-- ===========================================================================
-- 5. Quyền trên bảng cho basement_app
--    Không cấp DELETE (xóa mềm hoặc hủy bằng trạng thái), trừ 2 bảng dữ liệu dẫn xuất.
--    Bảng chỉ ghi thêm không cấp UPDATE.
-- ===========================================================================
GRANT SELECT, UPDATE ON organizations TO basement_app;
GRANT SELECT, INSERT, UPDATE ON
    branches, user_roles, seat_sessions, time_slots, price_rules, membership_plans, memberships,
    products, branch_products, orders, order_items, invoices, payments,
    books, book_copies, book_loans, announcements, ideas, idea_comments
TO basement_app;
GRANT SELECT, INSERT, DELETE ON seat_session_segments TO basement_app;     -- tính lại khi hóa đơn chưa thu tiền
GRANT SELECT, INSERT, UPDATE, DELETE ON book_embeddings TO basement_app;   -- tính lại embedding
GRANT SELECT, INSERT ON book_search_logs, announcement_reads TO basement_app;
-- users: mọi cột trừ password_hash khi đọc (đọc mật khẩu qua app.login_lookup)
GRANT SELECT (id, organization_id, full_name, phone, email, member_code, is_guest,
              created_at, updated_at, deleted_at) ON users TO basement_app;
GRANT INSERT, UPDATE ON users TO basement_app;

-- ===========================================================================
-- 6. Bật RLS và chính sách cách ly tổ chức (RESTRICTIVE, áp cho mọi bảng)
--    Các policy PERMISSIVE ở mục 7 quyết định ai thấy dòng nào trong tổ chức;
--    policy RESTRICTIVE này luôn được AND thêm vào.
-- ===========================================================================
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations FORCE ROW LEVEL SECURITY;
CREATE POLICY org_isolation ON organizations AS RESTRICTIVE FOR ALL TO basement_app
    USING (id = app.org_id()) WITH CHECK (id = app.org_id());

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'branches', 'users', 'user_roles', 'seat_sessions', 'time_slots', 'price_rules',
        'membership_plans', 'memberships', 'seat_session_segments', 'products', 'branch_products',
        'orders', 'order_items', 'invoices', 'payments', 'books', 'book_copies', 'book_loans',
        'book_embeddings', 'book_search_logs', 'announcements', 'announcement_reads',
        'ideas', 'idea_comments']
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY org_isolation ON %I AS RESTRICTIVE FOR ALL TO basement_app '
                       'USING (organization_id = app.org_id()) WITH CHECK (organization_id = app.org_id())', t);
    END LOOP;
END $$;

-- ===========================================================================
-- 7. Policy theo vai trò (PERMISSIVE)
-- ===========================================================================

-- ---------- A. Nền tảng --------------------------------------------------------
CREATE POLICY org_select ON organizations FOR SELECT TO basement_app USING (true);
CREATE POLICY org_update_owner ON organizations FOR UPDATE TO basement_app
    USING (app.is_owner()) WITH CHECK (app.is_owner());

-- Danh sách chi nhánh công khai trong tổ chức (khách xem để chọn nơi đến).
CREATE POLICY branches_select ON branches FOR SELECT TO basement_app USING (true);
CREATE POLICY branches_insert_owner ON branches FOR INSERT TO basement_app WITH CHECK (app.is_owner());
CREATE POLICY branches_update_manager ON branches FOR UPDATE TO basement_app
    USING (app.can_manage_branch(id)) WITH CHECK (app.can_manage_branch(id));

-- users: tự xem mình; nhân viên xem khách toàn tổ chức (cột cơ bản, đã giới hạn ở GRANT).
CREATE POLICY users_select_self ON users FOR SELECT TO basement_app USING (id = app.user_id());
CREATE POLICY users_select_staff ON users FOR SELECT TO basement_app USING (app.is_staff());
CREATE POLICY users_update_self ON users FOR UPDATE TO basement_app
    USING (id = app.user_id()) WITH CHECK (id = app.user_id() AND NOT is_guest);
CREATE POLICY users_insert_guest ON users FOR INSERT TO basement_app
    WITH CHECK (app.is_staff() AND is_guest);
CREATE POLICY users_update_guest ON users FOR UPDATE TO basement_app
    USING (app.is_staff() AND is_guest) WITH CHECK (app.is_staff() AND is_guest);
CREATE POLICY users_insert_manager ON users FOR INSERT TO basement_app
    WITH CHECK (app.is_manager());                                   -- tạo tài khoản nhân viên
CREATE POLICY users_update_owner ON users FOR UPDATE TO basement_app
    USING (app.is_owner()) WITH CHECK (app.is_owner());

-- user_roles: tự xem vai trò của mình; quản lý xem vai trò trong phạm vi mình.
CREATE POLICY user_roles_select_self ON user_roles FOR SELECT TO basement_app USING (user_id = app.user_id());
CREATE POLICY user_roles_select_manager ON user_roles FOR SELECT TO basement_app
    USING (app.can_manage_branch(branch_id));
CREATE POLICY user_roles_insert_owner ON user_roles FOR INSERT TO basement_app WITH CHECK (app.is_owner());
CREATE POLICY user_roles_update_owner ON user_roles FOR UPDATE TO basement_app
    USING (app.is_owner()) WITH CHECK (app.is_owner());
-- Quản lý chi nhánh chỉ cấp/thu hồi vai trò staff tại chi nhánh mình.
CREATE POLICY user_roles_insert_manager ON user_roles FOR INSERT TO basement_app
    WITH CHECK (role = 'staff' AND branch_id IS NOT NULL AND app.can_manage_branch(branch_id));
CREATE POLICY user_roles_update_manager ON user_roles FOR UPDATE TO basement_app
    USING (role = 'staff' AND branch_id IS NOT NULL AND app.can_manage_branch(branch_id))
    WITH CHECK (role = 'staff' AND branch_id IS NOT NULL AND app.can_manage_branch(branch_id));

-- ---------- B. Phiên ngồi ------------------------------------------------------
CREATE POLICY seat_sessions_select_staff ON seat_sessions FOR SELECT TO basement_app
    USING (app.can_access_branch(branch_id));
CREATE POLICY seat_sessions_select_own ON seat_sessions FOR SELECT TO basement_app
    USING (customer_id = app.user_id());
CREATE POLICY seat_sessions_insert_staff ON seat_sessions FOR INSERT TO basement_app
    WITH CHECK (app.can_access_branch(branch_id) AND opened_by = app.user_id());
CREATE POLICY seat_sessions_update_staff ON seat_sessions FOR UPDATE TO basement_app
    USING (app.can_access_branch(branch_id)) WITH CHECK (app.can_access_branch(branch_id));

-- ---------- C. Giá và gói ------------------------------------------------------
-- Bảng giá công khai trong tổ chức; quản lý chi nhánh sửa bảng giá chi nhánh mình.
CREATE POLICY time_slots_select ON time_slots FOR SELECT TO basement_app USING (true);
CREATE POLICY time_slots_write ON time_slots FOR INSERT TO basement_app WITH CHECK (app.can_manage_branch(branch_id));
CREATE POLICY time_slots_update ON time_slots FOR UPDATE TO basement_app
    USING (app.can_manage_branch(branch_id)) WITH CHECK (app.can_manage_branch(branch_id));

CREATE POLICY price_rules_select ON price_rules FOR SELECT TO basement_app USING (true);
CREATE POLICY price_rules_write ON price_rules FOR INSERT TO basement_app WITH CHECK (app.can_manage_branch(branch_id));
CREATE POLICY price_rules_update ON price_rules FOR UPDATE TO basement_app
    USING (app.can_manage_branch(branch_id)) WITH CHECK (app.can_manage_branch(branch_id));

CREATE POLICY membership_plans_select ON membership_plans FOR SELECT TO basement_app USING (true);
CREATE POLICY membership_plans_write ON membership_plans FOR INSERT TO basement_app WITH CHECK (app.is_owner());
CREATE POLICY membership_plans_update ON membership_plans FOR UPDATE TO basement_app
    USING (app.is_owner()) WITH CHECK (app.is_owner());

-- Gói dùng ở mọi chi nhánh nên nhân viên mọi chi nhánh đều xem được gói của khách.
CREATE POLICY memberships_select_own ON memberships FOR SELECT TO basement_app USING (customer_id = app.user_id());
CREATE POLICY memberships_select_staff ON memberships FOR SELECT TO basement_app USING (app.is_staff());
CREATE POLICY memberships_insert_staff ON memberships FOR INSERT TO basement_app WITH CHECK (app.is_staff());
CREATE POLICY memberships_update_staff ON memberships FOR UPDATE TO basement_app
    USING (app.is_staff()) WITH CHECK (app.is_staff());

CREATE POLICY segments_select_staff ON seat_session_segments FOR SELECT TO basement_app
    USING (app.can_access_branch(branch_id));
CREATE POLICY segments_select_own ON seat_session_segments FOR SELECT TO basement_app
    USING (EXISTS (SELECT 1 FROM seat_sessions s
                   WHERE s.id = seat_session_segments.seat_session_id AND s.customer_id = app.user_id()));
CREATE POLICY segments_insert_staff ON seat_session_segments FOR INSERT TO basement_app
    WITH CHECK (app.can_access_branch(branch_id));
CREATE POLICY segments_delete_staff ON seat_session_segments FOR DELETE TO basement_app
    USING (app.can_access_branch(branch_id));

-- ---------- D. Bán hàng và thanh toán -------------------------------------------
CREATE POLICY products_select ON products FOR SELECT TO basement_app USING (true);
CREATE POLICY products_write ON products FOR INSERT TO basement_app WITH CHECK (app.is_owner());
CREATE POLICY products_update ON products FOR UPDATE TO basement_app
    USING (app.is_owner()) WITH CHECK (app.is_owner());

CREATE POLICY branch_products_select ON branch_products FOR SELECT TO basement_app USING (true);
CREATE POLICY branch_products_write ON branch_products FOR INSERT TO basement_app
    WITH CHECK (app.can_access_branch(branch_id));
CREATE POLICY branch_products_update ON branch_products FOR UPDATE TO basement_app
    USING (app.can_access_branch(branch_id)) WITH CHECK (app.can_access_branch(branch_id));

CREATE POLICY orders_select_staff ON orders FOR SELECT TO basement_app USING (app.can_access_branch(branch_id));
CREATE POLICY orders_select_own ON orders FOR SELECT TO basement_app USING (customer_id = app.user_id());
CREATE POLICY orders_insert_staff ON orders FOR INSERT TO basement_app
    WITH CHECK (app.can_access_branch(branch_id) AND created_by = app.user_id());
CREATE POLICY orders_update_staff ON orders FOR UPDATE TO basement_app
    USING (app.can_access_branch(branch_id)) WITH CHECK (app.can_access_branch(branch_id));

CREATE POLICY order_items_select_staff ON order_items FOR SELECT TO basement_app USING (app.can_access_branch(branch_id));
CREATE POLICY order_items_select_own ON order_items FOR SELECT TO basement_app
    USING (EXISTS (SELECT 1 FROM orders o WHERE o.id = order_items.order_id AND o.customer_id = app.user_id()));
CREATE POLICY order_items_insert_staff ON order_items FOR INSERT TO basement_app
    WITH CHECK (app.can_access_branch(branch_id));
CREATE POLICY order_items_update_staff ON order_items FOR UPDATE TO basement_app
    USING (app.can_access_branch(branch_id)) WITH CHECK (app.can_access_branch(branch_id));

CREATE POLICY invoices_select_staff ON invoices FOR SELECT TO basement_app USING (app.can_access_branch(branch_id));
CREATE POLICY invoices_select_own ON invoices FOR SELECT TO basement_app USING (customer_id = app.user_id());
CREATE POLICY invoices_insert_staff ON invoices FOR INSERT TO basement_app
    WITH CHECK (app.can_access_branch(branch_id) AND created_by = app.user_id());
CREATE POLICY invoices_update_staff ON invoices FOR UPDATE TO basement_app
    USING (app.can_access_branch(branch_id)) WITH CHECK (app.can_access_branch(branch_id));

CREATE POLICY payments_select_staff ON payments FOR SELECT TO basement_app USING (app.can_access_branch(branch_id));
CREATE POLICY payments_select_own ON payments FOR SELECT TO basement_app
    USING (EXISTS (SELECT 1 FROM invoices i WHERE i.id = payments.invoice_id AND i.customer_id = app.user_id()));
CREATE POLICY payments_insert_staff ON payments FOR INSERT TO basement_app
    WITH CHECK (app.can_access_branch(branch_id) AND created_by = app.user_id());
CREATE POLICY payments_update_staff ON payments FOR UPDATE TO basement_app
    USING (app.can_access_branch(branch_id)) WITH CHECK (app.can_access_branch(branch_id));

-- ---------- E. Thư viện --------------------------------------------------------
-- Danh mục sách và bản sao công khai trong tổ chức (tìm sách, lọc sách còn ở chi nhánh).
CREATE POLICY books_select ON books FOR SELECT TO basement_app USING (true);
CREATE POLICY books_write ON books FOR INSERT TO basement_app WITH CHECK (app.is_manager());
CREATE POLICY books_update ON books FOR UPDATE TO basement_app
    USING (app.is_manager()) WITH CHECK (app.is_manager());

CREATE POLICY book_copies_select ON book_copies FOR SELECT TO basement_app USING (true);
CREATE POLICY book_copies_write ON book_copies FOR INSERT TO basement_app
    WITH CHECK (app.can_access_branch(branch_id));
CREATE POLICY book_copies_update ON book_copies FOR UPDATE TO basement_app
    USING (app.can_access_branch(branch_id)) WITH CHECK (app.can_access_branch(branch_id));

CREATE POLICY book_loans_select_staff ON book_loans FOR SELECT TO basement_app USING (app.can_access_branch(branch_id));
CREATE POLICY book_loans_select_own ON book_loans FOR SELECT TO basement_app USING (customer_id = app.user_id());
CREATE POLICY book_loans_insert_staff ON book_loans FOR INSERT TO basement_app
    WITH CHECK (app.can_access_branch(branch_id) AND issued_by = app.user_id());
CREATE POLICY book_loans_update_staff ON book_loans FOR UPDATE TO basement_app
    USING (app.can_access_branch(branch_id)) WITH CHECK (app.can_access_branch(branch_id));

-- ---------- F. Tìm kiếm sách bằng AI --------------------------------------------
CREATE POLICY book_embeddings_select ON book_embeddings FOR SELECT TO basement_app USING (true);
CREATE POLICY book_embeddings_insert ON book_embeddings FOR INSERT TO basement_app WITH CHECK (app.is_manager());
CREATE POLICY book_embeddings_update ON book_embeddings FOR UPDATE TO basement_app
    USING (app.is_manager()) WITH CHECK (app.is_manager());
CREATE POLICY book_embeddings_delete ON book_embeddings FOR DELETE TO basement_app USING (app.is_manager());

-- Ai cũng ghi được nhật ký tìm kiếm của chính mình (hoặc ẩn danh).
CREATE POLICY search_logs_insert ON book_search_logs FOR INSERT TO basement_app
    WITH CHECK (user_id IS NULL OR user_id = app.user_id());
-- Đọc nhật ký: chủ/quản lý toàn chuỗi thấy hết; quản lý chi nhánh thấy dòng NULL + dòng chi nhánh mình.
CREATE POLICY search_logs_select ON book_search_logs FOR SELECT TO basement_app
    USING (app.can_manage_branch(branch_id) OR (branch_id IS NULL AND app.is_manager()));

-- ---------- H. Thông báo -------------------------------------------------------
-- Người đọc: đã đến giờ đăng, chưa hết hạn, chưa xóa, đúng đối tượng và phạm vi.
--   Nhân viên: audience staff/all, dòng NULL (toàn chuỗi) + dòng chi nhánh mình.
--   Khách (không có vai trò nhân viên): audience customers/all, mọi chi nhánh trong tổ chức.
CREATE POLICY announcements_select_reader ON announcements FOR SELECT TO basement_app
    USING (deleted_at IS NULL AND publish_at <= now() AND (expires_at IS NULL OR expires_at > now())
           AND app.user_id() IS NOT NULL
           AND (  (audience IN ('staff', 'all') AND app.is_staff()
                   AND (branch_id IS NULL OR app.can_access_branch(branch_id)))
               OR (audience IN ('customers', 'all') AND NOT app.is_staff())));
-- Người soạn: thấy cả bài đã lên lịch, hết hạn, đã xóa trong phạm vi mình quản lý.
CREATE POLICY announcements_select_manager ON announcements FOR SELECT TO basement_app
    USING (app.can_manage_branch(branch_id));
CREATE POLICY announcements_insert ON announcements FOR INSERT TO basement_app
    WITH CHECK (app.can_manage_branch(branch_id) AND created_by = app.user_id());
CREATE POLICY announcements_update ON announcements FOR UPDATE TO basement_app
    USING (app.can_manage_branch(branch_id)) WITH CHECK (app.can_manage_branch(branch_id));

-- Bảng kế thừa: phạm vi lấy từ announcements qua EXISTS (bảng cha cũng bị RLS lọc).
CREATE POLICY announcement_reads_select_own ON announcement_reads FOR SELECT TO basement_app
    USING (user_id = app.user_id());
CREATE POLICY announcement_reads_select_manager ON announcement_reads FOR SELECT TO basement_app
    USING (EXISTS (SELECT 1 FROM announcements a
                   WHERE a.id = announcement_reads.announcement_id AND app.can_manage_branch(a.branch_id)));
CREATE POLICY announcement_reads_insert ON announcement_reads FOR INSERT TO basement_app
    WITH CHECK (user_id = app.user_id()
                AND EXISTS (SELECT 1 FROM announcements a WHERE a.id = announcement_reads.announcement_id));

-- ---------- I. Bảng ý tưởng (chỉ nhân viên trở lên) --------------------------------
-- Thấy: bài toàn chuỗi + bài chi nhánh mình. Bài pending hoặc đã xóa mềm chỉ tác giả
-- (với pending) và người duyệt (quản lý phạm vi đó) thấy.
CREATE POLICY ideas_select ON ideas FOR SELECT TO basement_app
    USING (app.is_staff()
           AND (branch_id IS NULL OR app.can_access_branch(branch_id))
           AND (app.can_manage_branch(branch_id)
                OR (deleted_at IS NULL AND (status <> 'pending' OR author_id = app.user_id()))));
CREATE POLICY ideas_insert ON ideas FOR INSERT TO basement_app
    WITH CHECK (app.is_staff() AND author_id = app.user_id() AND status = 'pending' AND deleted_at IS NULL
                AND (branch_id IS NULL OR app.can_access_branch(branch_id)));
-- Tác giả sửa bài của mình khi còn pending.
CREATE POLICY ideas_update_author ON ideas FOR UPDATE TO basement_app
    USING (author_id = app.user_id() AND status = 'pending' AND deleted_at IS NULL)
    WITH CHECK (author_id = app.user_id() AND status = 'pending' AND deleted_at IS NULL);
-- Người duyệt đổi trạng thái, ghi người xử lý, xóa mềm.
CREATE POLICY ideas_update_moderator ON ideas FOR UPDATE TO basement_app
    USING (app.can_manage_branch(branch_id)) WITH CHECK (app.can_manage_branch(branch_id));

-- Bảng kế thừa: thấy bình luận khi thấy bài (EXISTS tới ideas, đã qua RLS).
CREATE POLICY idea_comments_select ON idea_comments FOR SELECT TO basement_app
    USING (EXISTS (SELECT 1 FROM ideas i WHERE i.id = idea_comments.idea_id)
           AND (deleted_at IS NULL OR author_id = app.user_id()
                OR EXISTS (SELECT 1 FROM ideas i WHERE i.id = idea_comments.idea_id
                           AND app.can_manage_branch(i.branch_id))));
CREATE POLICY idea_comments_insert ON idea_comments FOR INSERT TO basement_app
    WITH CHECK (author_id = app.user_id() AND app.is_staff()
                AND EXISTS (SELECT 1 FROM ideas i WHERE i.id = idea_comments.idea_id AND i.deleted_at IS NULL));
CREATE POLICY idea_comments_update ON idea_comments FOR UPDATE TO basement_app
    USING (author_id = app.user_id()
           OR EXISTS (SELECT 1 FROM ideas i WHERE i.id = idea_comments.idea_id AND app.can_manage_branch(i.branch_id)))
    WITH CHECK (author_id = app.user_id()
           OR EXISTS (SELECT 1 FROM ideas i WHERE i.id = idea_comments.idea_id AND app.can_manage_branch(i.branch_id)));


-- Giả định
-- 1. Chạy bằng tài khoản có CREATEROLE và BYPASSRLS (cần để tạo basement_security); bảng thuộc basement_owner.
-- 2. Ứng dụng gán app.organization_id và app.user_id bằng set_config(..., true) trong từng giao dịch; với connection pool phải dùng phạm vi giao dịch, không dùng phạm vi phiên.
-- 3. Ai là người thao tác (closed_by, voided_by, confirmed_by…) do service gán bằng app.user_id; RLS chỉ kiểm tra người tạo (opened_by, created_by, issued_by, author_id).
-- 4. Quản trị nhiều tổ chức (thêm tổ chức mới) không đi qua basement_app mà dùng vai trò quản trị riêng có BYPASSRLS, ngoài phạm vi file này.
-- 5. Các hàm kiểm tra vai trò được gọi theo từng dòng; với dữ liệu mô phỏng 3 chi nhánh là đủ nhanh, khi lớn cần đo lại.

