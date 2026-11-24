-- 01_schema.sql — Basement: lược đồ cơ sở dữ liệu (25 bảng)
-- Yêu cầu: PostgreSQL 16+, pgvector 0.5+ (HNSW), btree_gist.
-- Nội dung: extension, enum, bảng, PK, UNIQUE, CHECK, FK, partial unique index, index.
-- Trigger updated_at: 02_triggers.sql. RLS và vai trò DB: 03_rls.sql.
-- Chạy bằng vai trò migration (chủ sở hữu schema), không chạy bằng vai trò ứng dụng.

BEGIN;

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

COMMIT;

-- Giả định
-- 1. Chạy bằng vai trò migration sở hữu schema public; vai trò ứng dụng và RLS khai báo ở 03_rls.sql.
-- 2. Mọi FK dùng NO ACTION (không xóa dây chuyền) vì dữ liệu được xóa mềm hoặc hủy bằng trạng thái.
-- 3. Tìm toàn văn dùng cấu hình 'simple' (PostgreSQL không có từ điển tiếng Việt), giữ nguyên dấu.
-- 4. Quy tắc liên bảng (amount = total khi xác nhận, chỉ void khi chưa thu tiền, trừ tồn kho…) do service xử lý.
-- 5. HNSW index tạo khi đã chốt mô hình; trước đó tìm vector vẫn chạy được nhưng quét tuần tự.
