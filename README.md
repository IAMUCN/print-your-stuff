# Hostel Print Automation Documentation

This repository contains the architecture, specifications, and implementation designs for the Hostel Print Automation system ("print-your-stuff").

## Overview & Architecture Baseline

A low-friction, cost-free print management pipeline designed for hostel operations:
- **Telegram Bot (Student Interface)**: Minimal conversational interface for students to submit print jobs (PDF, DOC/DOCX, Images), select print settings (pages, copies, B&W/color, image grids), and receive a sequential Job Code (e.g. `#1047`).
- **Unified Cloud Backend (Render + Supabase)**: Single Node.js/TypeScript service (Fastify + grammY + pdf-lib + Drizzle ORM) deployed on Render's free web tier. Manages REST APIs, Telegram Bot webhooks, PDF page-counting, and on-demand image grid generation. Backed by persistent PostgreSQL hosted on Supabase.
- **Desktop Admin App (Flutter Desktop for Windows)**: Sleek, high-contrast Material 3 monochrome application running on the hostel admin's PC. Displays the live print queue, handles file inspection/preview, connects to the HP Smart Tank 589 via the Windows Print Spooler, and converts DOC/DOCX files locally using headless LibreOffice with an explicit admin approval safeguard.

## Storage & Network Economics
- **Telegram Cloud Storage**: Actual student uploads remain in Telegram via `file_id`. The Telegram bot token is never exposed to the desktop client.
- **On-Demand Streaming**: Files and composed multi-image PDFs are streamed to the desktop app on-demand through the authenticated backend, consuming a tiny fraction of Render's free 100 GB/month egress allowance. No external paid object storage is required.

## Documentation Index

### Telegram Bot & Shared Cloud Backend
- [PRD](file:///E:/PROJECTS/print-your-stuff/telegram-bot/initial-md-files/PRD.md)
- [TRD](file:///E:/PROJECTS/print-your-stuff/telegram-bot/initial-md-files/TRD.md)
- [Backend Schema](file:///E:/PROJECTS/print-your-stuff/telegram-bot/initial-md-files/backend-schema.md)
- [User Flow](file:///E:/PROJECTS/print-your-stuff/telegram-bot/initial-md-files/user-flow.md)
- [UI/UX Specification](file:///E:/PROJECTS/print-your-stuff/telegram-bot/initial-md-files/UI-UX.md)

### Desktop Admin Application
- [PRD](file:///E:/PROJECTS/print-your-stuff/desktop-app/initial-md-files/PRD.md)
- [TRD](file:///E:/PROJECTS/print-your-stuff/desktop-app/initial-md-files/TRD.md)
- [Backend Schema View](file:///E:/PROJECTS/print-your-stuff/desktop-app/initial-md-files/backend-schema.md)
- [User Flow](file:///E:/PROJECTS/print-your-stuff/desktop-app/initial-md-files/user-flow.md)
- [UI/UX Specification](file:///E:/PROJECTS/print-your-stuff/desktop-app/initial-md-files/UI-UX.md)
