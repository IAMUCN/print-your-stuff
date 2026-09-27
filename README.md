# 🖨️ Print Your Stuff — Automated Hostel & Campus Print Management

An end-to-end, zero-cost, self-hosted automated print management system designed for college hostels, campuses, libraries, and small offices.

Students submit print jobs through a user-friendly **Telegram Bot**, which queues the job in a **Cloud Backend**. The hostel admin manages and prints the queue with a single click using a modern **Flutter Windows Desktop App**, which interfaces directly with the local printer via the Windows Print Spooler.

---

## 🏗️ System Architecture

```mermaid
flowchart LR
    subgraph Students
        TG[Telegram App]
    end

    subgraph Cloud Infrastructure
        BOT[Fastify + grammY Backend<br/>(Render Free Tier)]
        DB[(PostgreSQL Database<br/>Supabase Free Tier)]
        TG_CLOUD[Telegram File Cloud<br/>(Free Storage)]
    end

    subgraph Admin Workstation
        DESKTOP[Flutter Windows App<br/>(Admin Dashboard)]
        LIBRE[LibreOffice Headless<br/>(DOC/DOCX -> PDF)]
        SPOOLER[Windows Print Spooler<br/>(PrintTicket V4 Engine)]
        PRINTER[Physical Printer<br/>(e.g., HP Smart Tank)]
    end

    TG -->|Uploads PDF/DOCX| BOT
    BOT -->|Metadata & Drafts| DB
    BOT -->|Streams Files| TG_CLOUD
    DESKTOP -->|Polls Queue / Auth| BOT
    DESKTOP -->|Downloads File On-Demand| BOT
    DESKTOP -->|Converts DOCX| LIBRE
    DESKTOP -->|Sends Raw PDF & DPI/Quality| SPOOLER
    SPOOLER -->|Prints| PRINTER
```

---

## ✨ Features

- **📱 Telegram Bot for Students**:
  - Direct upload of single or batch PDF documents.
  - Microsoft Word document support (`.doc`, `.docx`) with automatic server/desktop conversion.
  - Interactive inline keyboard to configure **Color vs. Black & White**, **Copies**, and custom **Page Ranges** (e.g. `1-5`).
  - Automatic grouping of multi-file messages into a single print job.
  - Clean student status updates (`Print job #1004 printed.`).
  - Helpful commands: `/start`, `/jobs`, `/name`, `/clear`, `/status`, `/help`.

- **⚡ Cloud Backend (Fastify + grammY + Drizzle ORM)**:
  - 100% Free Tier compatible (Render + Supabase).
  - Uses Telegram's cloud infrastructure for file storage (no expensive S3 buckets needed).
  - Production-ready with automatic Telegram Webhook support on Render or local long-polling.
  - JWT-authenticated REST APIs for the admin desktop client.
  - Automatic cleanup and expiration of abandoned drafts and completed jobs.

- **🖥️ Desktop Admin Application (Flutter Windows)**:
  - High-contrast, clean Material 3 desktop UI.
  - Live queue polling with search by Job Code (e.g. `#1004`) or student name.
  - Full-fidelity PDF inspection and multi-page preview dialog before printing.
  - Headless LibreOffice integration for safe local DOC/DOCX conversion with an approval modal.
  - Real-time hardware print tracking via Windows Management Instrumentation (WMI) and Spooler APIs.
  - Hardware PrintTicket XML configuration (overriding Quality to Draft/Normal/Best and DPI to 300/600/1200 on HP and standard Windows V4 print drivers).

---

## 🚀 Quick Start / Forking Guide

Follow these steps to deploy your own instance of the system.

### Prerequisites

1. **Node.js** (v20+ recommended) and `npm`.
2. **PostgreSQL Database** (Create a free project on [Supabase](https://supabase.com) or [Neon](https://neon.tech)).
3. **Telegram Bot Token** (Create a free bot via [@BotFather](https://t.me/botfather) on Telegram).
4. **Flutter SDK** (v3.22+ for building the Windows desktop app).
5. **Windows 10/11 PC** connected to your local printer.
6. *(Optional)* **LibreOffice** installed on the Windows PC for Word document conversion.

---

### Step 1: Database Setup (Supabase)

1. Create a free project at [supabase.com](https://supabase.com).
2. Go to **Project Settings** → **Database** → **Connection string** (URI).
3. Use the **Session pooler** or **Direct connection** URI (e.g., `postgresql://postgres.[ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres?sslmode=require`).

---

### Step 2: Backend Configuration & Deployment

#### Option A: Deploy to Render (Recommended for 24/7 Cloud Hosting)

1. Fork this repository to your GitHub account.
2. Log in to [Render](https://dashboard.render.com).
3. Click **New +** → **Blueprint** (or **Web Service**).
4. Connect your forked repository. Render will automatically detect `render.yaml`.
5. Fill in the environment variables:
   - `DATABASE_URL`: Your Supabase PostgreSQL connection string.
   - `TELEGRAM_BOT_TOKEN`: The token given by `@BotFather`.
   - `JWT_SECRET`: A secure random string for admin tokens.
   - `ADMIN_USERNAME`: Admin login username (e.g., `admin`).
   - `ADMIN_PASSWORD`: Admin login password (e.g., `adminpassword123`).
   - `WEBHOOK_URL`: Your Render service URL (e.g., `https://your-service.onrender.com`).
6. Click **Deploy**. Render will install dependencies, build TypeScript, and automatically register your Telegram webhook!

#### Option B: Run Backend Locally (Development)

1. Clone your fork and enter the backend directory:
   ```bash
   cd telegram-bot
   ```
2. Copy the environment template:
   ```bash
   cp .env.example .env
   ```
3. Open `.env` and fill in your `DATABASE_URL`, `TELEGRAM_BOT_TOKEN`, and admin credentials. (Leave `WEBHOOK_URL` empty to use local long-polling mode).
4. Install dependencies and run database migrations:
   ```bash
   npm install
   npm run build
   ```
5. Start the backend:
   ```bash
   npm start
   # Or for development with live reload:
   npm run dev
   ```

---

### Step 3: Desktop App Setup (Admin Workstation)

1. Navigate to the desktop app folder:
   ```bash
   cd desktop-app
   ```
2. Fetch Flutter packages:
   ```bash
   flutter pub get
   ```
3. Run the Windows app:
   ```bash
   flutter run -d windows
   ```
4. On the login screen:
   - Click the **Settings (⚙️)** icon in the top right.
   - Enter your backend URL:
     - Cloud Render URL: `https://your-service.onrender.com`
     - Local dev URL: `http://localhost:3000`
   - Log in using your `ADMIN_USERNAME` and `ADMIN_PASSWORD`.
5. Select your default printer and configure global print quality/DPI in the Settings dialog.

---

## ⚙️ Environment Variables Reference

| Variable | Description | Example |
| :--- | :--- | :--- |
| `PORT` | HTTP port for the Fastify server | `3000` (Local) / `10000` (Render) |
| `HOST` | Host binding interface | `0.0.0.0` |
| `DATABASE_URL` | PostgreSQL connection URI | `postgresql://user:pass@host:5432/db?sslmode=require` |
| `TELEGRAM_BOT_TOKEN`| Bot API token from `@BotFather` | `8508527057:AA...` |
| `WEBHOOK_URL` | Public HTTPS domain for Telegram Webhooks | `https://your-app.onrender.com` (leave empty for polling) |
| `JWT_SECRET` | Secret key for signing desktop JWTs | `super_secret_jwt_key_2026` |
| `ADMIN_USERNAME` | Default admin username seeded on start | `admin` |
| `ADMIN_PASSWORD` | Default admin password seeded on start | `adminpassword123` |

---

## 📂 Project Structure

```
print-your-stuff/
├── .github/                 # CI/CD Workflows
├── render.yaml              # Render Cloud deployment blueprint
├── package.json             # Root monorepo build orchestrator
├── telegram-bot/            # Backend API & Telegram Bot
│   ├── src/
│   │   ├── api/routes/      # REST endpoints (auth, jobs, stream)
│   │   ├── bot/             # Telegram bot handler & UI keyboards
│   │   ├── db/              # Drizzle ORM schema & seed scripts
│   │   ├── services/        # PDF inspection & Telegram file streaming
│   │   ├── config.ts        # Environment configuration
│   │   └── index.ts         # Fastify & Grammy entry point
│   ├── Dockerfile           # Optional containerized build
│   └── package.json
└── desktop-app/             # Flutter Windows Admin App
    ├── lib/
    │   ├── models/          # Job data models & enums
    │   ├── screens/         # Dashboard & Login screens
    │   ├── services/        # Printer spooler, API client, LibreOffice
    │   ├── widgets/         # Preview dialogs, settings, printer chips
    │   └── main.dart        # Flutter entry point
    └── pubspec.yaml
```

---

## 🔒 Security Best Practices

- **Never commit `.env` files**: All secrets, database credentials, and bot tokens must remain in environment variables.
- **Telegram Storage**: Sensitive documents are never stored permanently on third-party servers; files are streamed securely directly from Telegram's encrypted API.
- **Admin Authentication**: All desktop communication is encrypted with TLS and authenticated with signed JWT bearer tokens.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
Feel free to fork, customize, and deploy it for your campus, hostel, or organization!
