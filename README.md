# Basement Platform (Monorepo)

Dự án nền tảng **Basement Platform** được xây dựng theo kiến trúc **Monorepo** với trình quản lý gói **pnpm** (pnpm workspaces), kết hợp hệ sinh thái công nghệ hiện đại cho cả Frontend và Backend.

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
│       │   ├── prisma/             # PrismaService tích hợp withBranch RLS
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

- **Node.js**: >= `20.x` (LTS khuyến nghị)
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
# Chạy ngoài Docker (localhost):
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/basement_db?schema=public"
# Chạy trong container Docker:
# DATABASE_URL="postgresql://postgres:postgres@postgres:5432/basement_db?schema=public"

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

```bash
# Tạo Prisma Client
pnpm --filter @basement/api prisma generate

# Áp dụng migration (bao gồm kích hoạt pgvector và chính sách Row-Level Security)
pnpm --filter @basement/api prisma migrate dev

# (Tùy chọn) Mở giao diện Prisma Studio để kiểm tra dữ liệu
pnpm --filter @basement/api prisma studio
```

#### Kiểm thử Row-Level Security (RLS)
API cung cấp sẵn endpoint kiểm tra kết nối database và cơ chế phân quyền cô lập dữ liệu theo từng chi nhánh (`app.current_branch`):

```bash
# Kiểm tra tự động tính cô lập dữ liệu giữa 3 chi nhánh (HCM, DAD, VCA):
curl http://localhost:3001/health/rls-test

# Truy vấn dữ liệu riêng cho từng chi nhánh:
curl "http://localhost:3001/health/rls-test?branch=HCM"
curl "http://localhost:3001/health/rls-test?branch=DAD"
curl "http://localhost:3001/health/rls-test?branch=VCA"
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
