# Frontend Development Rules (`apps/web`)

## 1. Cấu trúc thư mục & Phân tách Component
Tuân thủ cấu trúc chuẩn trong `apps/web/src/`:
- `app/`: Chỉ chứa routing, `layout.tsx`, `page.tsx`, `loading.tsx`, `error.tsx`. Không viết logic fetch dữ liệu phức tạp hay file dài quá 200 dòng trực tiếp trong `page.tsx`.
- `components/ui/`: Component nguyên thủy từ `shadcn/ui` (`Button`, `Input`, `Dialog`, `Sheet`, `Skeleton`, `Badge`, `Tooltip`...).
- `components/layout/`: Khung điều hướng dùng chung (`TopNavbar`, `BranchFolderTabs`, `AdminSidebar`).
- `components/features/booking/`: Nghiệp vụ đặt chỗ (`SeatMapGrid`, `SeatItem`, `BookingSummaryPanel`).
- `components/features/books/`: Nghiệp vụ tìm sách AI (`SemanticBookSearch`, `BookResultTable`, `BookMobileCard`).
- `lib/`: `api-client.ts` (wrapper gọi API), `utils.ts` (hàm `cn()`), `constants.ts` (danh sách chi nhánh, khung giờ chuẩn).
- `types/`: Định nghĩa interface TypeScript khớp với DTO của `apps/api`.

**Server vs. Client Component:**
- Giữ mặc định là **Server Component** để tối ưu tốc độ tải trang.
- Chỉ khai báo `'use client'` ở các component thực sự cần state hoặc tương tác người dùng (`SeatMapGrid`, `BranchFolderTabs`, ô tìm kiếm, modal xác nhận).

---

## 2. Quy chuẩn UI Design System (Light Mode — Blueprint & Folder Tabs)
Cấm tự ý hardcode mã màu hoặc font chữ ngoài bộ chuẩn đã chốt:

### Bảng màu chuẩn
- **Nền lưới chính (Blueprint):** `#F4F4F3` (`--bg-blueprint`)
- **Nền thẻ / ô ghế mặc định (Concrete):** `#ECECEB` (`--surface-concrete`)
- **Viền mảnh (Hairline):** `#D4D4D2` (`--border-hairline`)
- **Chữ chính & nút CTA (Ink):** `#141414` (`--ink-primary`)
- **Chữ mô tả phụ:** `#525252` (`text-neutral-600`)
- **Nhấn thao tác / Tab active (Signal Orange):** `#DF3B1E` (`--accent-orange`)
- **Trạng thái ghế (Status Dots):**
  - Ghế trống (`AVAILABLE`): Chấm tròn xanh lá `#15803D` (`text-emerald-700`).
  - Ghế đang chọn (`SELECTED`): Nền hoặc viền nổi bật cam đỏ `#DF3B1E`.
  - Ghế đã bận (`OCCUPIED`): Chấm tròn xám `#858582`, vô hiệu hóa thao tác click.

### Typography
- **`Plus Jakarta Sans`:** Dùng cho toàn bộ tiêu đề phân khu, thanh điều hướng, tên sách và văn bản mô tả.
- **`JetBrains Mono` (`font-mono`):** Bắt buộc dùng cho các thông số kỹ thuật: chỉ mục phân khu (`/ 01`, `/ 02`), mã chi nhánh (`[01 HCM]`, `[02 DAD]`, `[03 VCA]`), mã ghế (`A01`), khung giờ (`18:00 - 21:00`), độ tương đồng AI (`98%`) và mã kệ sách (`Kệ A1-12`).

### Hình khối & Responsive
- **Nền lưới kỹ thuật:** Khu vực sơ đồ ghế bắt buộc áp dụng class `.bg-blueprint-grid`.
- **Bo góc:** Nút bấm chính (CTA) và Badge dùng dáng **Pill** (`rounded-full`); thanh chọn chi nhánh dùng **Folder Tabs** xếp lớp (`rounded-t-lg`); khung khu vực/bảng dữ liệu giữ góc vuông hoặc bo nhẹ (`0px–4px`); ô ghế bo `6px` (`rounded-md`).
- **Kiểm thử đa thiết bị:** Mọi PR giao diện phải kiểm tra hiển thị ở **Desktop (`1440px`, khung `max-w-7xl`)**, **Tablet (`768px`)** và **Mobile (`375px`)**. Bảng kết quả tìm sách trên Desktop phải tự động chuyển thành danh sách thẻ xếp dọc (`BookMobileCard`) trên Mobile.

---

## 3. Quản lý Ngữ cảnh Chi nhánh (Multi-Branch RLS)
- **Single Source of Truth:** Mã chi nhánh hiện tại (`HCM` | `DAD` | `VCA`) được đồng bộ giữa tham số URL (`?branch=HCM`) và thanh `BranchFolderTabs`.
- **Tự động đính kèm Header:** Mọi request từ `src/lib/api-client.ts` sang `apps/api` bắt buộc phải tự động gắn header `x-branch-code: <MÃ_CHI_NHÁNH>` để khớp với cơ chế Row-Level Security ở Backend.
- **Reset khi chuyển chi nhánh:** Ngay khi người dùng bấm sang tab chi nhánh khác, phải xóa ghế đang chọn tạm trong `BookingSummaryPanel` và gọi lại dữ liệu sơ đồ ghế + kho sách của chi nhánh mới.

---

## 4. Gọi API, Trạng thái Tải & Xử lý Lỗi
- **Server State:** Sử dụng **TanStack Query** (`useQuery`, `useMutation`) cho toàn bộ thao tác đọc/ghi dữ liệu từ API.
- **Xử lý Render Cold Start:** Server Staging trên Render ngủ đông sau 15 phút (mất 30–50 giây khởi động lại). Mọi khu vực tải dữ liệu phải hiển thị `Skeleton` đúng kích thước khung thật kèm thông báo trạng thái nhẹ (*"Đang kết nối máy chủ Basement..."*), không để màn hình trắng.
- **Xử lý tranh chấp đặt chỗ (`409 Conflict`):** Khi xác nhận đặt ghế mà API trả về mã `409` (do người khác vừa đặt trước một nhịp), phải bắt riêng lỗi này để hiện thông báo `Toast` (*"Ghế này vừa có người đặt, vui lòng chọn ghế khác"*) và tự động refetch lại sơ đồ ghế.

---

## 5. TypeScript, Monorepo & Quy ước Git
- Bật `"strict": true` trong `tsconfig.json`; cấm sử dụng kiểu `any`.
- Cài thư viện cho FE luôn chạy từ thư mục gốc monorepo: `pnpm --filter web add <tên-gói>`.
- Tuyệt đối không import code, Prisma Client hay biến môi trường từ `apps/api`. Biến môi trường của FE phải có tiền tố `NEXT_PUBLIC_` và khai báo mẫu trong `apps/web/.env.example`.
- Đặt tên nhánh và commit theo phạm vi: `feat(web): <mô-tả>`, `fix(web): <mô-tả>`.