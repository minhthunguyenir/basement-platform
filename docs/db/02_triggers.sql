-- 02_triggers.sql — Basement: tự cập nhật updated_at
-- Chạy sau 01_schema.sql, bằng vai trò migration.
-- Gắn vào 22 bảng có updated_at. Bỏ qua 3 bảng chỉ ghi thêm: seat_session_segments, book_search_logs, announcement_reads.

BEGIN;

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

COMMIT;

-- Giả định
-- 1. Ứng dụng không tự gửi updated_at; nếu có gửi, trigger vẫn ghi đè bằng giờ máy chủ.
-- 2. Trigger chạy cả khi UPDATE không đổi giá trị nào (PostgreSQL không tự bỏ qua); service tránh UPDATE thừa.
-- 3. Không thêm trigger nghiệp vụ (đổi trạng thái hóa đơn, trừ tồn kho, cập nhật book_copies.status): service xử lý trong cùng giao dịch.
-- 4. Hàm nằm ở schema public, chủ sở hữu là vai trò migration; vai trò ứng dụng không cần quyền gì thêm để trigger chạy.
