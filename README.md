# Basement Platform (Monorepo)

Dự án nền tảng **Basement Platform** được xây dựng theo kiến trúc **Monorepo** với trình quản lý gói **pnpm** (pnpm workspaces), kết hợp hệ sinh thái công nghệ hiện đại cho cả Frontend và Backend.

---

## 🌐 Môi trường thử nghiệm (Staging Environments)

Bảng tổng hợp 3 tầng hạ tầng đã triển khai trên môi trường thử nghiệm:

| Tầng hạ tầng (Layer) | Nền tảng triển khai | Đường dẫn truy cập (URL) | Chức năng & Kiểm thử |
| :--- | :--- | :--- | :--- |
| **Frontend Web** | Vercel | [https://basement-platform.vercel.app](https://basement-platform.vercel.app) | Giao diện web ứng dụng Next.js |
| **Backend API & Swagger Docs** | Render | [https://basement-platform.onrender.com/api/docs](https://basement-platform.onrender.com/api/docs) | Tài liệu API tương tác và kiểm thử Swagger UI |
| **Database Health & RLS Verification** | Neon PostgreSQL + Render | [https://basement-platform.onrender.com/health/rls-test](https://basement-platform.onrender.com/health/rls-test) | Kiểm tra kết nối cơ sở dữ liệu và xác thực tính toàn vẹn Row-Level Security (RLS) |

> ⚠️ **Lưu ý vận hành (Render Free Tier):** Máy chủ Backend API được triển khai trên gói Render Free, do đó server sẽ tự chuyển sang trạng thái nghỉ sau 15 phút không có truy cập và mất khoảng **30–50 giây** để khởi động lại ở lượt gọi đầu tiên.

---

## 📑 Mục lục
1. [Tech Stack](#-tech-stack)
2. [Cấu trúc Thư mục Dự án](#-cấu-trúc-thư-mục-dự-án)
3. [Yêu cầu Hệ thống](#-yêu-cầu-hệ-thống-prerequisites)
4. [Hướng dẫn Cài đặt & Chạy Local (Setup)](#-hướng-dẫn-cài-đặt--chạy-local-setup)
    - [Clone Repository](#1-clone-repository)
    - [Cài đặt Dependencies](#2-cài-đặt-dependencies)
    - [Cấu hình Biến môi trường](#3-cấu-hình-biến-môi-trường)
    - [Khởi chạy với Docker Compose (Tất cả dịch vụ)](#4-khởi-chạy-với-docker-compose-tất-cả-dịch-vụ)
    - [Cấu hình Prisma & Database Migration (RLS)](#5-cấu-hình-prisma--database-migration-rls)
    - [Chạy Ứng dụng trong Môi trường Phát triển (Native pnpm)](#6-chạy-ứng-dụng-trong-môi-trường-phát-triển-native-pnpm)
5. [Các Lệnh pnpm Thường Dùng](#-các-lệnh-pnpm-thường-dùng)
6. [Quy trình Tạo Nhánh & Pull Request (Git Workflow)](#-quy-trình-tạo-nhánh--pull-request-git-workflow)
    - [Quy ước Đặt tên Nhánh](#quy-ước-đặt-tên-nhánh)
    - [Quy chuẩn Commit (Conventional Commits)](#quy-chuẩn-commit-conventional-commits)
    - [Quy trình Làm việc Chi tiết](#quy-trình-làm-việc-chi-tiết)
    - [Tiêu chuẩn & Checklist Tạo Pull Request](#tiêu-chuẩn--checklist-tạo-pull-request)
7. [Quy ước Phát triển Monorepo (Development Guidelines)](#-quy-ước-phát-triển-monorepo-development-guidelines)
8. [UI Design System & Quy chuẩn Frontend (`apps/web`)](#-ui-design-system--quy-chuẩn-frontend-appsweb)
9. [Tiến độ Triển khai (Roadmap)](#-tiến-độ-triển-khai-roadmap)

---

## 🚀 Tech Stack

- **Monorepo Management:** [pnpm](https://pnpm.io/) Workspaces (hỗ trợ caching/turbo nếu cần mở rộng)
- **Frontend (`apps/web`):**
    - [Next.js](https://nextjs.org/) (App Router, React, TypeScript)
    - [Tailwind CSS](https://tailwindcss.com/)
- **Backend (`apps/api`):**
    - [NestJS](https://nestjs.com/) (TypeScript)
    - [Prisma ORM](https://www.prisma.io/)
- **Data & Storage:**
    - [PostgreSQL](https://www.postgresql.org/) với extension **[pgvector](https://github.com/pgvector/pgvector)** (hỗ trợ Vector Search / AI Embeddings)
    - [Redis](https://redis.io/) (Cache layer, Rate limiting & Background Queues)

---

## 📁 Cấu trúc Thư mục Dự án

```text
basement-platform/
├── apps/
│   ├── web/                        # Frontend Application (Next.js + Tailwind CSS)
│   │   ├── src/
│   │   │   ├── app/                # Next.js App Router
│   │   │   └── components/
│   │   ├── public/
│   │   ├── Dockerfile.dev          # Docker build dev hỗ trợ hot-reload (Port 3000)
│   │   ├── tailwind.config.ts
│   │   ├── tsconfig.json
│   │   └── package.json            # Name: @basement/web
│   │
│   └── api/                        # Backend Application (NestJS + Prisma)
│       ├── src/
│       │   ├── prisma/             # PrismaService.withContext(): gán ngữ cảnh RLS (tổ chức + người dùng)
│       │   ├── health/             # Health check & test RLS endpoint
│       │   └── main.ts             # Port 3001
│       ├── prisma/
│       │   ├── schema.prisma       # Prisma Schema (PostgreSQL + pgvector)
│       │   └── migrations/         # Chứa migration SQL & RLS policies
│       ├── Dockerfile.dev          # Docker build dev hỗ trợ hot-reload (Port 3001)
│       ├── tsconfig.json
│       └── package.json            # Name: @basement/api
│
├── packages/                       # Shared packages & configurations
│   ├── shared/                     # Shared DTOs, types, utilities
│   │   └── package.json            # Name: @basement/shared
│   ├── eslint-config/              # Shared ESLint configuration
│   └── tsconfig/                   # Shared TypeScript configurations
│
├── .github/
│   └── workflows/
│       └── ci.yml                  # GitHub Actions CI (lint, build workspace)
├── .dockerignore                   # Loại trừ node_modules, .next, dist khi build image
├── docker-compose.yml              # Dựng đồng thời postgres, redis, api, web
├── .env.example                    # Template biến môi trường chuẩn
├── .env                            # Biến môi trường local
├── .gitignore                      # Git ignore file (bảo vệ secrets, cache, OS files)
├── package.json                    # Root package.json (chạy song song dev, build, lint)
├── pnpm-workspace.yaml             # Cấu hình workspace của pnpm
└── README.md                       # Tài liệu hướng dẫn dự án
```

---

## ⚙️ Yêu cầu Hệ thống (Prerequisites)

- **Node.js**: `24.x` LTS, tối thiểu `24.9` (khai báo trong `.nvmrc` và `engines`). Jest của API cần bản này để nạp các package ESM-only của NestJS 12.
- **pnpm**: >= `9.x` (khuyến nghị `pnpm@12.x`)
    - Cài đặt pnpm nếu chưa có: `npm install -g pnpm` hoặc `corepack enable && corepack prepare pnpm@latest --activate`
- **Docker & Docker Compose**: Để chạy PostgreSQL (pgvector), Redis, API và Web.
- **Git**

---

## 🛠️ Hướng dẫn Cài đặt & Chạy Local (Setup)

### 1. Clone Repository
```bash
git clone https://github.com/minhthunguyenir/basement-platform.git
cd basement-platform
```

### 2. Cài đặt Dependencies
Cài đặt toàn bộ dependencies cho toàn bộ workspace thông qua pnpm:
```bash
pnpm install
```

### 3. Cấu hình Biến môi trường
Sao chép file `.env.example` sang `.env` ở thư mục gốc:

```bash
cp .env.example .env
```

Các tham số cấu hình chính:
```env
# Database (PostgreSQL + pgvector)
# Runtime: BẮT BUỘC role basement_app (bị RLS lọc). Migration: DIRECT_URL (owner/superuser).
# Chạy ngoài Docker (localhost):
DATABASE_URL="postgresql://basement_app:basement_app_local@localhost:5432/basement_db?schema=public"
DIRECT_URL="postgresql://postgres:postgres@localhost:5432/basement_db?schema=public"
# Chạy trong container Docker: thay localhost bằng postgres
BASEMENT_APP_PASSWORD=basement_app_local
DEFAULT_ORGANIZATION_ID=   # uuid tổ chức, dùng tạm đến khi có xác thực

POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=basement_db
POSTGRES_PORT=5432

# Redis
REDIS_URL="redis://localhost:6379"
REDIS_HOST=localhost
REDIS_PORT=6379

# Backend API
PORT=3001
API_PORT=3001
API_URL="http://localhost:3001"

# Frontend Web
WEB_PORT=3000
NEXT_PUBLIC_API_URL="http://localhost:3001"
```

### 4. Khởi chạy với Docker Compose (Tất cả dịch vụ)
Dự án được cấu hình sẵn file `docker-compose.yml` ở thư mục gốc để khởi chạy **toàn bộ 4 dịch vụ** (`postgres`, `redis`, `api`, `web`) chỉ bằng một câu lệnh:

```bash
docker compose up -d
```

Các dịch vụ sẽ sẵn sàng:
- **Frontend Web (`web`):** [http://localhost:3000](http://localhost:3000) (hỗ trợ hot-reload qua volume mount)
- **Backend API (`api`):** [http://localhost:3001](http://localhost:3001) (hỗ trợ watch mode)
- **Swagger API Docs:** [http://localhost:3001/api/docs](http://localhost:3001/api/docs) (giao diện tương tác Swagger UI)
- **PostgreSQL (`postgres`):** `localhost:5432` (kèm pgvector)
- **Redis (`redis`):** `localhost:6379`

> 💡 **Mẹo:** Nếu chỉ muốn chạy Database và Redis trên Docker, sau đó chạy code trực tiếp trên máy bằng pnpm, dùng lệnh:
> ```bash
> docker compose up -d postgres redis
> pnpm dev
> ```

Nội dung cấu hình `docker-compose.yml`:
```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    container_name: basement_postgres
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      POSTGRES_DB: ${POSTGRES_DB:-basement_db}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-basement_db}"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: basement_redis
    restart: always
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  api:
    build:
      context: .
      dockerfile: apps/api/Dockerfile.dev
    container_name: basement_api
    restart: always
    ports:
      - "3001:3001"
    environment:
      - NODE_ENV=development
      - PORT=3001
      - DATABASE_URL=postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@postgres:5432/${POSTGRES_DB:-basement_db}?schema=public
      - REDIS_URL=redis://redis:6379
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    volumes:
      - ./apps/api:/app/apps/api
      - /app/apps/api/node_modules
      - /app/node_modules
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  web:
    build:
      context: .
      dockerfile: apps/web/Dockerfile.dev
    container_name: basement_web
    restart: always
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
      - PORT=3000
      - HOSTNAME=0.0.0.0
      - NEXT_PUBLIC_API_URL=http://localhost:3001
    volumes:
      - ./apps/web:/app/apps/web
      - /app/apps/web/node_modules
      - /app/node_modules
    depends_on:
      - api

volumes:
  postgres_data:
  redis_data:
```

### 5. Cấu hình Prisma & Database Migration (RLS)
Áp dụng Prisma migration lên PostgreSQL và sinh Prisma Client:

Lược đồ gốc nằm ở [`docs/db`](./docs/db/README.md) (25 bảng, RLS theo tổ chức và người dùng). Migration baseline `apps/api/prisma/migrations/*_basement_baseline` được ghép từ `01_schema.sql` + `02_triggers.sql` + `03_rls.sql`.

```bash
# Tạo Prisma Client
pnpm --filter @basement/api prisma generate

# Áp dụng migration (dùng DIRECT_URL): pgvector, 25 bảng, trigger, role DB và chính sách RLS
pnpm --filter @basement/api prisma migrate deploy

# Đặt mật khẩu cho role ứng dụng (một lần, khớp với DATABASE_URL)
docker exec -i basement_postgres psql -U postgres -d basement_db -c "ALTER ROLE basement_app PASSWORD 'basement_app_local';"

# Nạp dữ liệu mẫu (1 tổ chức, 3 chi nhánh HCM/DAD/VCA, nhân viên, khách, bảng giá, sách, 3 phiên đang mở).
# Chạy lại được nhiều lần; chỉ dùng cho dev/staging. Tổ chức mẫu: DEFAULT_ORGANIZATION_ID=00000000-0000-4000-a000-000000000001
pnpm --filter @basement/api db:seed

# (Tùy chọn) Mở giao diện Prisma Studio để kiểm tra dữ liệu
pnpm --filter @basement/api prisma studio
```

> Tạo migration mới: luôn dùng `prisma migrate dev --create-only`, đọc lại SQL rồi mới áp dụng. Prisma không biểu diễn được partial index, exclusion constraint, CHECK và policy RLS, nên phải bảo đảm migration không xóa chúng.

#### Kiểm thử Row-Level Security (RLS)

```bash
# Kiểm tra cấu hình đang chạy: kết nối bằng basement_app, 25/25 bảng ép RLS, không có ngữ cảnh thì không đọc được dữ liệu
curl http://localhost:3001/health/rls-test

# Bộ 50 ca kiểm thử phân quyền (tự ROLLBACK, không để lại dữ liệu; CI chạy tự động ở job db-rls)
docker exec -i basement_postgres psql -U postgres -d basement_db -v ON_ERROR_STOP=1 < docs/db/04_rls_tests.sql
```

### 6. Chạy Ứng dụng trong Môi trường Phát triển (Native pnpm)
Nếu phát triển trực tiếp trên máy chủ máy trạm (không qua container web/api):
```bash
# Chạy đồng thời cả Frontend và Backend bằng script song song ở root:
pnpm dev
```
Hoặc chạy riêng từng ứng dụng theo bộ lọc `--filter`:
```bash
# Chạy riêng Backend NestJS (Port 3001)
pnpm --filter @basement/api dev

# Chạy riêng Frontend Next.js (Port 3000)
pnpm --filter @basement/web dev
```

---

## 💻 Các Lệnh pnpm Thường Dùng

| Lệnh | Mục đích |
| :--- | :--- |
| `pnpm install` | Cài đặt toàn bộ dependencies trong monorepo |
| `pnpm dev` | Khởi chạy toàn bộ apps song song ở chế độ phát triển |
| `pnpm --filter @basement/web dev` | Chỉ chạy riêng ứng dụng Next.js frontend |
| `pnpm --filter @basement/api dev` | Chỉ chạy riêng ứng dụng NestJS backend |
| `pnpm build` | Build tất cả ứng dụng & packages |
| `pnpm --filter @basement/web build` | Build riêng frontend Next.js |
| `pnpm --filter @basement/api build` | Build riêng backend NestJS |
| `pnpm lint` | Chạy kiểm tra cú pháp ESLint/oxlint trên toàn workspace |
| `pnpm test` | Chạy unit tests |
| `pnpm --filter @basement/api prisma migrate dev` | Tạo và áp dụng Prisma migration mới |
| `pnpm --filter @basement/api prisma generate` | Cập nhật Prisma Client sau khi sửa schema |
| `pnpm --filter @basement/api prisma studio` | Mở GUI quản lý dữ liệu Prisma Studio |

---

## 🌿 Quy trình Tạo Nhánh & Pull Request (Git Workflow)

Nhằm đảm bảo chất lượng code và tính ổn định của hệ thống, toàn bộ thành viên tuân thủ quy trình Git workflow chuẩn sau:

### Quy ước Đặt tên Nhánh
Tất cả các nhánh được tạo ra từ `main` (hoặc `develop`) và đặt tên theo quy tắc:

`<tiền-tố>/<mô-tả-ngắn-gọn>`

Các tiền tố hợp lệ:
- `feat/` hoặc `feature/`: Phát triển tính năng mới (Ví dụ: `feat/web-landing-page`, `feat/api-auth-jwt`, `feat/pgvector-similarity-search`)
- `fix/` hoặc `bugfix/`: Sửa lỗi (Ví dụ: `fix/web-mobile-menu`, `fix/api-redis-cache-ttl`)
- `hotfix/`: Sửa lỗi khẩn cấp trực tiếp cho môi trường production (Ví dụ: `hotfix/fix-auth-crash`)
- `refactor/`: Tái cấu trúc mã nguồn không làm thay đổi hành vi nghiệp vụ (Ví dụ: `refactor/api-prisma-service`)
- `chore/`: Cập nhật cấu hình build, dependencies, tooling (Ví dụ: `chore/update-pnpm-deps`)
- `docs/`: Thêm hoặc cập nhật tài liệu (Ví dụ: `docs/update-setup-guide`)

### Quy chuẩn Commit (Conventional Commits)
Thông điệp commit cần ngắn gọn, rõ nghĩa và tuân thủ định dạng:
`type(scope): subject`

- **Type:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`
- **Scope (tùy chọn):** `web`, `api`, `shared`, `prisma`, `docker`
- **Ví dụ:**
    - `feat(api): add vector similarity search endpoint with pgvector`
    - `feat(web): add responsive navigation bar with tailwind`
    - `fix(api): correct redis connection retry backoff`
    - `docs(readme): add pnpm setup and docker compose instructions`

### Quy trình Làm việc Chi tiết
1. **Đồng bộ nhánh chính trước khi làm việc:**
   ```bash
   git checkout main
   git pull origin main
   ```
2. **Tạo nhánh mới:**
   ```bash
   git checkout -b feat/ten-tinh-nang
   ```
3. **Phát triển và kiểm tra cục bộ:**
   Trước khi commit, đảm bảo code không phát sinh lỗi lint hoặc build:
   ```bash
   pnpm lint
   pnpm build
   ```
4. **Commit mã nguồn:**
   ```bash
   git add .
   git commit -m "feat(api): implement user authentication module"
   ```
5. **Đẩy nhánh lên GitHub:**
   ```bash
   git push -u origin feat/ten-tinh-nang
   ```
6. **Mở Pull Request (PR):**
   - Vào giao diện GitHub của repository và chọn **New Pull Request**.
   - Base branch: `main` (hoặc `develop`).
   - Compare branch: nhánh vừa tạo (`feat/ten-tinh-nang`).

### Tiêu chuẩn & Checklist Tạo Pull Request
Mỗi Pull Request cần cung cấp thông tin rõ ràng và vượt qua các tiêu chí sau:

- [ ] **Mô tả thay đổi:** Trình bày tóm tắt nội dung thay đổi và lý do thực hiện.
- [ ] **Kiểm thử cục bộ:**
    - [ ] Đã chạy `pnpm lint` thành công không có cảnh báo/lỗi nghiêm trọng.
    - [ ] Đã chạy `pnpm build` thành công trên toàn bộ workspace.
    - [ ] Đã kiểm tra tính tương thích của Prisma migration (nếu có cập nhật schema).
- [ ] **Biến môi trường:** Nếu có thêm biến môi trường mới, đã bổ sung vào `.env.example`.
- [ ] **Code Review:** Đã được ít nhất 01 thành viên khác review và phê duyệt (Approve) trước khi merge.
- [ ] **Merge Strategy:** Ưu tiên chọn **Squash and Merge** (hoặc **Rebase and Merge**) để giữ lịch sử commit trên nhánh chính gọn gàng.

---

## 📌 Quy ước Phát triển Monorepo (Development Guidelines)

- **Quản lý thư viện (`pnpm`):**
  - Luôn chạy lệnh cài đặt package từ thư mục gốc của monorepo kết hợp cờ `--filter` (ví dụ: `pnpm --filter @basement/api add <pkg>`).
  - Tuyệt đối không chạy `npm install` hay `yarn` bên trong `apps/api` hoặc `apps/web` để tránh sinh file lock thừa (`package-lock.json`, `yarn.lock`).
  - Nếu xảy ra xung đột (conflict) file `pnpm-lock.yaml`, ưu tiên giữ nguyên bản của nhánh `main` và chạy lại `pnpm install` ở thư mục gốc để tự động cập nhật lockfile hợp lệ.

- **Ranh giới Backend & Frontend:**
  - Tách riêng biệt biến môi trường: `apps/api/.env` dành riêng cho các khóa bảo mật, credentials database, redis; `apps/web/.env.local` chỉ chứa các biến có tiền tố `NEXT_PUBLIC_` được phép phơi bày cho trình duyệt.
  - Không import trực tiếp Prisma Client, ORM models hay các module Node.js chuyên biệt từ `apps/api` sang `apps/web`. Chia sẻ DTOs, interfaces và tiện ích chung thông qua package `packages/shared` (`@basement/shared`).

- **Quy ước Git & Commit:**
  - Đặt tiền tố commit rõ ràng theo phạm vi tác động cụ thể (ví dụ: `feat(api):`, `feat(web):`, `fix(db):`, `docs:`).
  - Hạn chế chỉnh sửa đồng thời các file cấu hình tại thư mục gốc (`package.json`, `pnpm-lock.yaml`, `.github/workflows/ci.yml`) trên nhiều nhánh cùng một lúc nhằm hạn chế xung đột merge.

- **Cơ chế Tự động Triển khai (Auto-Deploy):**
  - Mọi Pull Request khi được hợp nhất (merge) vào nhánh `main` đều tự động kích hoạt GitHub Actions CI để kiểm tra `lint` và `build`.
  - Sau khi CI hoàn tất thành công, webhook tự động triển khai phiên bản mới nhất lên đồng thời cả **Render** (Backend API & Swagger Docs) và **Vercel** (Frontend Web).

---

## 🎨 UI Design System & Quy chuẩn Frontend (`apps/web`)

Giao diện ứng dụng người dùng (`apps/web`) được thiết kế đồng bộ theo phong cách bản vẽ kỹ thuật kết hợp thẻ thư mục, đảm bảo tính thẩm mỹ, nhất quán và độ phản hồi cao trên mọi thiết bị:

- **Phong cách Thiết kế (Design Concept):**
  - **Light Mode — Architectural Blueprint & Folder Tabs:** Tái hiện không gian làm việc kiến trúc với hệ lưới kỹ thuật nền (`.bg-blueprint-grid`), khung phân khu sắc nét và hệ thống tab dạng bìa hồ sơ (`Folder Tabs`).
  - **Khả năng đáp ứng (Responsive Design):** Tối ưu hóa trải nghiệm trên 3 kích thước chuẩn: Desktop (`1440px`, khung `max-w-7xl`), Tablet (`768px`) và Mobile (`375px`). Trên thiết bị di động, bảng dữ liệu tự động chuyển đổi linh hoạt thành dạng thẻ danh sách xếp dọc.

- **Bảng màu Chuẩn (Color Palette):**
  - **Blueprint (`#F4F4F3`):** Màu nền lưới kỹ thuật chính (`--bg-blueprint`).
  - **Concrete (`#ECECEB`):** Màu bề mặt thẻ, khung hiển thị và ô ghế mặc định (`--surface-concrete`).
  - **Hairline (`#D4D4D2`):** Đường viền phân cách siêu mảnh (`--border-hairline`).
  - **Ink (`#141414`):** Màu chữ chính, tiêu đề phân khu và nút hành động chính CTA (`--ink-primary`).
  - **Signal Orange (`#DF3B1E`):** Màu điểm nhấn tương tác, trạng thái tab đang chọn và ghế đang thao tác (`--accent-orange`).
  - *Màu trạng thái phụ trợ:* Xanh lá (`#15803D`) cho ghế trống (`AVAILABLE`), Xám (`#858582`) cho ghế đã có người đặt (`OCCUPIED`).

- **Quy chuẩn Typography:**
  - **`Plus Jakarta Sans`:** Phông chữ chính cho toàn bộ giao diện, tiêu đề phân khu, thanh điều hướng và văn bản mô tả.
  - **`JetBrains Mono` (`font-mono`):** Bắt buộc dùng cho toàn bộ dữ liệu mang tính kỹ thuật: chỉ mục phân khu (`/ 01`, `/ 02`), mã chi nhánh (`[01 HCM]`, `[02 DAD]`, `[03 VCA]`), mã ghế (`A01`), khung giờ (`18:00 - 21:00`), tỷ lệ tương đồng vector AI (`98%`) và mã kệ sách (`Kệ A1-12`).

- **Công nghệ & Quy chuẩn Kỹ thuật:**
  - **Công nghệ cốt lõi:** `Next.js` (App Router), `Tailwind CSS`, `shadcn/ui` (Radix UI), `lucide-react` (iconography), `TanStack Query` (quản lý server state).
  - **Ngữ cảnh Đa chi nhánh (RLS):** Đồng bộ mã chi nhánh qua URL (`?branch=HCM`) và tự động gắn header `x-branch-code` trong mọi request API để kích hoạt PostgreSQL Row-Level Security.
  - **Xử lý Trạng thái Mạng:** Tích hợp sẵn `Skeleton` mô phỏng đúng khung hình để xử lý độ trễ khởi động lại (cold start 30–50s) của gói Render Free; xử lý độc lập mã lỗi `409 Conflict` khi xảy ra tranh chấp đặt chỗ đồng thời.
  - 📖 **Quy tắc chi tiết:** Tham khảo hướng dẫn phát triển toàn diện tại [FRONTEND_RULES.md](./apps/web/FRONTEND_RULES.md).
