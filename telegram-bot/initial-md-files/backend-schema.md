# Backend Schema — Supabase PostgreSQL & Drizzle ORM

The shared database is hosted on Supabase (PostgreSQL) and queried via Drizzle ORM in TypeScript.

## Sequence

```sql
CREATE SEQUENCE job_code_seq START WITH 1001 INCREMENT BY 1;
```

---

## 1. `users`
Stores student Telegram identities and administrator credentials.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | PRIMARY KEY, DEFAULT `gen_random_uuid()` | Internal user ID |
| `telegram_user_id` | `BIGINT` | UNIQUE, NULLABLE | Immutable Telegram user identifier |
| `username` | `TEXT` | UNIQUE, NULLABLE | Admin login username |
| `password_hash` | `TEXT` | NULLABLE | Admin bcrypt password hash |
| `display_name` | `TEXT` | NOT NULL | Student registration name or admin name |
| `role` | `user_role` | NOT NULL, DEFAULT `'STUDENT'` | Enum: `STUDENT`, `ADMIN` |
| `created_at` | `TIMESTAMPTZ`| NOT NULL, DEFAULT `NOW()` | Registration timestamp |
| `updated_at` | `TIMESTAMPTZ`| NOT NULL, DEFAULT `NOW()` | Last profile update |

---

## 2. `jobs`
Main print job header representing a single student submission.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | PRIMARY KEY, DEFAULT `gen_random_uuid()` | Job UUID |
| `job_code` | `BIGINT` | UNIQUE, NULLABLE | Sequential student Job Code (e.g. `1047`) |
| `user_id` | `UUID` | NOT NULL, FK `users.id` | Submitting student |
| `status` | `job_status`| NOT NULL, DEFAULT `'DRAFT'` | Enum: `DRAFT`, `WAITING`, `PRINTING`, `PRINTED`, `PARTIALLY_PRINTED`, `FAILED`, `CANCELLED` |
| `created_at` | `TIMESTAMPTZ`| NOT NULL, DEFAULT `NOW()` | Draft initiation timestamp |
| `submitted_at`| `TIMESTAMPTZ`| NULLABLE | Submission completion timestamp |
| `expires_at` | `TIMESTAMPTZ`| NULLABLE | 48h expiration for pending, 7d for completed |
| `updated_at` | `TIMESTAMPTZ`| NOT NULL, DEFAULT `NOW()` | Last state transition timestamp |

---

## 3. `job_files`
Individual files uploaded as part of a print job.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | PRIMARY KEY, DEFAULT `gen_random_uuid()` | File UUID |
| `job_id` | `UUID` | NOT NULL, FK `jobs.id` ON DELETE CASCADE | Associated job |
| `telegram_file_id`| `TEXT` | NOT NULL | Telegram Bot API file storage ID |
| `original_filename`| `TEXT`| NOT NULL | Display filename |
| `mime_type` | `TEXT` | NOT NULL | Validated MIME type |
| `size_bytes` | `BIGINT` | NOT NULL | File size in bytes (max 20 MB) |
| `input_type` | `input_type`| NOT NULL | Enum: `PDF`, `IMAGE`, `DOC`, `DOCX` |
| `page_count` | `INT` | NULLABLE | Parsed page count (populated on cloud for PDFs) |
| `sort_order` | `INT` | NOT NULL, DEFAULT `0` | Order of files in job |
| `created_at` | `TIMESTAMPTZ`| NOT NULL, DEFAULT `NOW()` | Upload timestamp |

---

## 4. `print_settings`
Configured print parameters for each file in a job.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | PRIMARY KEY, DEFAULT `gen_random_uuid()` | Settings UUID |
| `job_file_id` | `UUID` | NOT NULL, UNIQUE, FK `job_files.id` ON DELETE CASCADE | Target file |
| `page_range` | `TEXT` | NULLABLE | e.g. `'1-5'`, `'3,7,9-12'`. Null = all pages |
| `copies` | `INT` | NOT NULL, DEFAULT `1` | Number of copies |
| `color_mode` | `color_mode`| NOT NULL, DEFAULT `'BW'` | Enum: `COLOR`, `BW` |
| `pages_per_sheet`| `INT` | NOT NULL, DEFAULT `1` | Supported: `1`, `2` |
| `orientation` | `orientation`| NOT NULL, DEFAULT `'AUTO'` | Enum: `PORTRAIT`, `LANDSCAPE`, `AUTO` |
| `image_layout`| `image_layout`| NOT NULL, DEFAULT `'FIT'` | Enum: `ONE_PER_PAGE`, `TWO_PER_PAGE`, `FIT`, `ORIGINAL` |
| `created_at` | `TIMESTAMPTZ`| NOT NULL, DEFAULT `NOW()` | Configuration timestamp |

---

## 5. `print_attempts`
Records every physical print attempt initiated from the desktop workstation.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | PRIMARY KEY, DEFAULT `gen_random_uuid()` | Attempt UUID |
| `job_id` | `UUID` | NOT NULL, FK `jobs.id` ON DELETE CASCADE | Target job |
| `initiated_by`| `UUID` | NOT NULL, FK `users.id` | Admin who clicked Print |
| `status` | `attempt_status`| NOT NULL | Enum: `STARTED`, `PRINTED`, `PARTIALLY_PRINTED`, `FAILED`, `CANCELLED` |
| `started_at` | `TIMESTAMPTZ`| NOT NULL, DEFAULT `NOW()` | Attempt start |
| `completed_at`| `TIMESTAMPTZ`| NULLABLE | Attempt completion |
| `error_message`| `TEXT` | NULLABLE | Spooler error description if failed |
| `printer_name` | `TEXT` | NULLABLE | Target printer name (e.g. HP Smart Tank 589) |

---

## 6. `job_events`
Audit trail of important job lifecycle changes.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | PRIMARY KEY, DEFAULT `gen_random_uuid()` | Event UUID |
| `job_id` | `UUID` | NOT NULL, FK `jobs.id` ON DELETE CASCADE | Associated job |
| `event_type` | `TEXT` | NOT NULL | e.g. `JOB_SUBMITTED`, `SETTINGS_UPDATED`, `PRINT_STARTED`, `PRINT_COMPLETED`, `JOB_CANCELLED` |
| `metadata` | `JSONB` | NULLABLE | Contextual details (e.g. modified fields) |
| `created_at` | `TIMESTAMPTZ`| NOT NULL, DEFAULT `NOW()` | Event timestamp |
