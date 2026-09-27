# Hostel Print Automation — Telegram Bot & Unified Cloud Backend TRD

## 1. System Architecture

```text
Telegram Student
       |
       | HTTPS (Telegram Webhook)
       v
Unified Cloud Backend (Node.js / TypeScript + Fastify on Render)
       |
       +---> grammY Bot Engine
       +---> PDF & Image Engine (pdf-lib in-memory)
       +---> Admin REST API (/api/v1/admin/*, /api/v1/jobs/*)
       |
       +====================+=====================+
       |                                          |
       v                                          v
Supabase PostgreSQL                      Telegram Cloud Storage
(Persistent DB via Drizzle ORM)          (Original files via file_id)
```

### Key Principles
- **Unified Single-Service Deployment**: Fastify REST API and grammY Telegram webhook handler run in the same Node.js service, fitting entirely inside Render's single free web service instance (750 hours/month).
- **Zero Heavy Native Dependencies on Cloud**: No LibreOffice or headless browser runs on Render. PDF page counts and image-to-PDF grid composition are executed in-memory with `pdf-lib`, keeping memory usage under **80 MB RAM** (well below Render's 512 MB ceiling).
- **Bandwidth & Storage Economics**:
  - Ingress from Telegram to Render is free and unlimited.
  - Egress from Render to the Desktop Admin App consumes Render's free **100 GB/month** allowance (an average 2 MB job enables ~50,000 print jobs/month).
  - No external paid object storage is required.

## 2. Technology Stack
- **Runtime**: Node.js 20+ / TypeScript
- **Web Framework**: Fastify (low overhead, fast JSON serialization)
- **Telegram Bot Framework**: `grammY` with webhook adapter
- **Database & ORM**: Supabase PostgreSQL with `drizzle-orm` + `drizzle-kit`
- **PDF Manipulation**: `pdf-lib` (pure JS/TS, zero native binaries)
- **Image Processing**: `sharp` or lightweight buffer canvas (for sizing/fitting)
- **Authentication**: JWT (`@fastify/jwt`) with `bcrypt` for admin credentials

## 3. Telegram Webhook Integration
1. **Webhook Registration**: On startup, backend registers webhook with `https://api.telegram.org/bot<TOKEN>/setWebhook?url=<RENDER_URL>/api/v1/telegram/webhook`.
2. **Upload Handling**:
   - Bot receives `document` or `photo`.
   - Validates MIME type and file size ($\le$ 20 MB).
   - If PDF: downloads first few KB buffer via Telegram API to read page count via `pdf-lib`.
   - Records metadata (`file_id`, filename, MIME type, size, parsed page count) into Supabase PostgreSQL.
   - Associates file with student's active `DRAFT` job.

## 4. Backend REST API Endpoints (for Desktop Admin Client)
- `POST /api/v1/auth/login`: Admin credentials verification, returns JWT access token.
- `GET /api/v1/auth/me`: Verifies active admin session.
- `GET /api/v1/jobs/queue`: Returns pending jobs (`WAITING`, `PRINTING`) with ordered files and settings.
- `GET /api/v1/jobs/history`: Returns completed or cancelled jobs with 7-day pagination.
- `GET /api/v1/jobs/:id`: Detailed view of a specific job.
- `PATCH /api/v1/jobs/:id/settings`: Admin updates print settings (copies, page range, color mode).
- `POST /api/v1/jobs/:id/status`: Transitions job state (`WAITING` $\rightarrow$ `PRINTING` $\rightarrow$ `PRINTED` / `FAILED` / `CANCELLED`).
- `GET /api/v1/jobs/:id/files/:fileId/stream`: Streams original file from Telegram to desktop via authenticated proxy.
- `GET /api/v1/jobs/:id/composed-pdf`: Generates and streams print-ready composed PDF (e.g. 2-image grid) on-demand.

## 5. Job Lifecycle & State Transitions
- `DRAFT`: Student is actively uploading files or configuring settings in Telegram.
- `WAITING`: Student submitted job; sequential Job Code assigned (`#1001`+); awaiting in-person print approval.
- `PRINTING`: Admin clicked "Confirm Print" on desktop app; print attempt dispatched to Windows spooler.
- `PRINTED`: Spooler confirmed dispatch / print finished.
- `PARTIALLY_PRINTED`: Print attempt succeeded partially or interrupted.
- `FAILED`: Print job aborted or spooler returned unrecoverable error.
- `CANCELLED`: Student cancelled before submission or admin cancelled stale job.

## 6. Expiration & Retention Worker
- A lightweight scheduled interval task runs periodically:
  - Jobs with `status = 'WAITING'` and `created_at < NOW() - INTERVAL '48 HOURS'` $\rightarrow$ transitioned to `CANCELLED` (expired).
  - Jobs with `status IN ('PRINTED', 'CANCELLED', 'FAILED')` older than 7 days $\rightarrow$ archived.

## 7. Security Hardening
- Telegram `file_id` is an internal reference and never exposed as a public URL.
- The Telegram Bot Token is stored strictly as a server-side environment variable on Render; it is never transmitted to the desktop app.
- Desktop endpoints require `Authorization: Bearer <JWT>`.
- Admin passwords hashed with `bcrypt` (12 rounds).
