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

BEGIN;

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

ALTER FUNCTION app.is_staff()                     OWNER TO basement_security;
ALTER FUNCTION app.is_manager()                   OWNER TO basement_security;
ALTER FUNCTION app.is_owner()                     OWNER TO basement_security;
ALTER FUNCTION app.can_access_branch(uuid)        OWNER TO basement_security;
ALTER FUNCTION app.can_manage_branch(uuid)        OWNER TO basement_security;
ALTER FUNCTION app.branch_occupancy()             OWNER TO basement_security;
ALTER FUNCTION app.customer_active_session(uuid)  OWNER TO basement_security;
ALTER FUNCTION app.login_lookup(text)             OWNER TO basement_security;
ALTER FUNCTION app.register_customer(varchar, varchar, varchar, text, varchar) OWNER TO basement_security;

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

COMMIT;

-- Giả định
-- 1. Chạy bằng tài khoản có CREATEROLE và BYPASSRLS (cần để tạo basement_security); bảng thuộc basement_owner.
-- 2. Ứng dụng gán app.organization_id và app.user_id bằng set_config(..., true) trong từng giao dịch; với connection pool phải dùng phạm vi giao dịch, không dùng phạm vi phiên.
-- 3. Ai là người thao tác (closed_by, voided_by, confirmed_by…) do service gán bằng app.user_id; RLS chỉ kiểm tra người tạo (opened_by, created_by, issued_by, author_id).
-- 4. Quản trị nhiều tổ chức (thêm tổ chức mới) không đi qua basement_app mà dùng vai trò quản trị riêng có BYPASSRLS, ngoài phạm vi file này.
-- 5. Các hàm kiểm tra vai trò được gọi theo từng dòng; với dữ liệu mô phỏng 3 chi nhánh là đủ nhanh, khi lớn cần đo lại.
