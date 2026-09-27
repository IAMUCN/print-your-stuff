# Hostel Print Backend & Telegram Bot

Unified Node.js / TypeScript service providing the Fastify REST API for the Desktop Admin Workstation and the grammY Telegram Bot for student submissions.

## Features
- **grammY Telegram Bot**: Frictionless student onboarding, document/photo uploads, PDF page count extraction, print setting configuration, and sequential `#1001`+ Job Code issuance.
- **Fastify Admin REST API**: JWT-authenticated endpoints for queue monitoring, job details, settings editing, status updates, and file streaming.
- **In-Memory PDF Engine (`pdf-lib`)**: Zero LibreOffice cloud overhead (<50 MB RAM). Composes image grids (1 or 2 per page) directly into A4 PDFs.
- **Drizzle ORM & Supabase**: Persistent relational data model with automatic sequence management for sequential job codes.
- **Dual Bot Mode**: Runs seamlessly with **Long-Polling** in local development and **Webhooks** in production on Render.

---

## Prerequisites & API Keys Needed

To run this backend, you only need two credentials:
1. **Telegram Bot Token**:
   - Open Telegram and message `@BotFather`.
   - Send `/newbot`, name your bot (e.g. `HostelPrintBot`), and copy the HTTP API token provided.
2. **Supabase Database Connection String**:
   - Create a free project on [Supabase](https://supabase.com).
   - Go to **Project Settings** $\rightarrow$ **Database** $\rightarrow$ **Connection String** (URI).
   - Copy the URI (use port `6543` pooler or `5432` direct).

---

## Local Development Setup

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Fill in your credentials in `.env`:
   ```env
   DATABASE_URL=postgresql://postgres:[PASSWORD]@[HOST]:[PORT]/postgres?sslmode=require
   TELEGRAM_BOT_TOKEN=your_token_from_botfather
   ADMIN_USERNAME=admin
   ADMIN_PASSWORD=adminpassword123
   ```
   *(Leave `WEBHOOK_URL` empty to use local Long-Polling!)*

3. Run migrations and seed initial admin + job code sequence:
   ```bash
   npm run db:seed
   ```

4. Start development server with hot-reload:
   ```bash
   npm run dev
   ```

The REST API will be live at `http://localhost:3000` and the Telegram bot will immediately begin listening to messages!

---

## Deployment to Render (Free Tier)

1. Push this repository to GitHub.
2. Log in to [Render](https://render.com).
3. Click **New +** $\rightarrow$ **Web Service** $\rightarrow$ Connect your repository.
4. Select Root Directory: `telegram-bot`.
5. Environment: `Docker` (Render will automatically detect `Dockerfile`).
6. Add your Environment Variables:
   - `DATABASE_URL`: Your Supabase connection string.
   - `TELEGRAM_BOT_TOKEN`: Your Telegram Bot API token.
   - `WEBHOOK_URL`: Your Render service URL (e.g. `https://hostel-print-backend.onrender.com`).
   - `ADMIN_USERNAME`: `admin`
   - `ADMIN_PASSWORD`: A secure admin password.
7. Click **Create Web Service**.

Render will deploy the service and set up the Telegram webhook automatically!
