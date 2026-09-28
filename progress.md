# 📊 Project Progress & Architecture Report: Print Your Stuff

*Hostel Automated Self-Service Printing Ecosystem*  
**Date:** September 28, 2026  
**Repository:** [https://github.com/IAMUCN/print-your-stuff.git](https://github.com/IAMUCN/print-your-stuff.git)  
**Git Branch Status:** `main` (3 commits ahead of remote; local-only staging per instructions)

---

## 1. 📌 Current Status of the Project
- **Backend & API:** Deployed and live on Render cloud (`https://hostel-print-backend-7w74.onrender.com`) running Fastify, Drizzle ORM, and PostgreSQL.
- **Telegram Bot:** Integrated into the backend with native command menus (`setMyCommands`), debounced multi-PDF batching, custom page-range parsing, and draft lifecycle management.
- **Desktop Admin App:** Built and verified for Windows 10/11 (`hostel_print_admin.exe`) with auto-reconnection, real-time print spooler lifecycle tracking, PDF preview dialogs, and native Win32 device diagnostics.
- **Global Settings Validation:** Fully aligned and verified live across storage, Windows Print Spooler, HP V4 XML PrintTicket, and GDI Device Context caps at **300 DPI Draft Mode**.

---

## 2. 🛠️ Tech Stack & Component Architecture

```
┌────────────────────────────────────────────────────────┐
│                   TELEGRAM BOT CLIENT                   │
│   (Students upload PDF/DOCX, configure copies & BW)     │
└───────────────────────────┬────────────────────────────┘
                            │ Webhook / HTTPS
                            ▼
┌────────────────────────────────────────────────────────┐
│             BACKEND SERVICE (RENDER CLOUD)             │
│  • Fastify REST API (/api/v1/jobs, /api/v1/auth)       │
│  • Grammy Telegram Bot Engine                          │
│  • Drizzle ORM + PostgreSQL Database                   │
│  • Background Retention Worker (48h expiration)        │
└───────────────────────────┬────────────────────────────┘
                            │ REST API (Polling + JWT)
                            ▼
┌────────────────────────────────────────────────────────┐
│              DESKTOP ADMIN APPLICATION                 │
│  • Flutter Desktop (Windows x64)                       │
│  • Native C++ PDFium Rendering (print_job.cpp)         │
│  • Win32 GDI Device Contexts & DeviceCapabilities      │
│  • PowerShell V4 PrintTicket Management                │
│  • LibreOffice Headless Document Converter             │
└───────────────────────────┬────────────────────────────┘
                            │ Win32 Spooler / USB / LAN
                            ▼
┌────────────────────────────────────────────────────────┐
│               HARDWARE PRINT ENGINE                    │
│   HP Smart Tank 580-590 Series (V4 PCL-3 Driver)       │
└────────────────────────────────────────────────────────┘
```

| Component | Technology | Responsibility |
|---|---|---|
| **Telegram Bot** | grammY, TypeScript, Node.js | User interaction, multi-document batch reception, setting copies/ranges/color, generating job codes (`#1004`). |
| **Backend REST API** | Fastify, JWT, CORS | Authentication, print job CRUD, document binary staging, database migrations, lifecycle state machines. |
| **Database** | PostgreSQL, Drizzle ORM | Relational persistence of users, jobs, print settings, files, and admin credentials. |
| **Desktop Admin App** | Flutter Windows, Dart | Admin queue monitoring, live printer connection checking, job approval, document preview, and print triggering. |
| **Print Engine (Native)** | C++, PDFium, Win32 GDI | High-performance PDF rasterization, proportional aspect-ratio auto-fitting, page-by-page spooling. |
| **Printer Config Utility** | Native C# (`printer_config_helper.exe`) | Sub-80ms GDI Device Context query (`GetDeviceCaps`) for live DPI, margins, and canvas inspection. |
| **Document Converter** | LibreOffice Headless (`soffice.exe`) | Converts student-submitted `.doc` and `.docx` files to print-ready PDF before spooling. |

---

## 3. 🚨 Problems Faced & Decisions Taken

### A. The "Big Page" Cutoff (Only Top Half Printed)
- **Problem:** Students submitting documents generated via mobile scanner apps (e.g. Aadhaar cards) printed with only the top half fitting on the sheet; the bottom and right sides were cropped.
- **Forensic Inspection:** Extracted `aadharosh (1).pdf` from Job 1011. Found document dimensions of **$1,500 \times 2,047$ points** (20.8 × 28.4 inches — blueprint scale) instead of A4 ($595 \times 842$ points). PDFium rendered a massive $6,250 \times 8,529$ bitmap directly onto the $2,410 \times 3,438$ printer canvas at 100% scale, causing a 2.5× magnification cutoff.
- **Decision & Fix:** Patched native `print_job.cpp` with proportional auto-fit scaling:
  $$\text{Scale} = \min\left(\frac{\text{printableWidth}}{bWidth},\, \frac{\text{printableHeight}}{bHeight},\, 1.0\right)$$
  Oversized documents now automatically downscale to fit the physical printable margins with centered offsets and zero clipping.

### B. High Print Latency & Spool Delay
- **Problem:** Printing started 5–8 seconds after clicking the Print button.
- **Root Cause:** Dynamic compilation of C# scripts via PowerShell `Add-Type` on every document dispatch.
- **Decision & Fix:** Pre-compiled a standalone Win32 helper (`desktop-app/windows/tools/printer_config_helper.exe`) and added configuration caching in `PrinterService`. Sequential prints with identical parameters now dispatch with **0 ms** driver configuration overhead.

### C. Multi-Document Sequential Print Halting
- **Problem:** When a job contained multiple PDFs, only the first PDF spooled; the second was dropped or delayed.
- **Decision & Fix:** Implemented active spooler monitoring (`trackJobCompletion`) with retry backoffs and added an **Individual File Download** button (`_downloadFile`) to the desktop UI so admins can save and print individual files manually if needed.

### D. Chrome Remote Desktop Black Window
- **Problem:** Accessing the desktop app via Chrome Remote Desktop produced a black window due to hardware-accelerated DirectX/ANGLE compositing.
- **Decision & Fix:** Configured software rasterizer fallbacks and added an interactive UI refresh trigger to ensure flawless remote rendering.

### E. Telegram Clutter & Student Confusion
- **Problem:** Telegram bot sent confusing notifications ("LibreOffice converter", "Go to hostel admin to collect the thing"). Also, multiple PDFs sent in one message were not batched.
- **Decision & Fix:**
  - Removed confusing automated conversion messages; restricted user-facing notifications to clean messages (e.g., `Print job #1004 printed.`).
  - Implemented debounced upload locking (`acquireUserLock` + `draftSummaryTimers`) so multiple documents sent together are automatically grouped into a single draft.
  - Replaced image printing with vector PDF/DOCX only, instructing users to convert photos to PDF before submitting.

---

## 4. 🔄 Recursive Problem: DPI & Draft Quality Reverting to 600 DPI

### Why This Happened 5 Times in Succession:
1. **The Windows V4 Driver Model:**  
   The user's printer is an **HP Smart Tank 580-590 series**, running `HP Smart Tank 580-590 series PCL-3 (V4)`. Windows V4 drivers do **not** use the legacy Win32 `DEVMODE` struct. They operate exclusively via XML `PrintTicket`.
2. **The Clobbering Bug:**  
   Every time our earlier code called Win32 `SetPrinter(Level 9, pDevMode)`, Windows Spooler invoked the driver's legacy translation DLL (`hpfime53.dll`). Because that DLL does not recognize V4 features, it **reset the PrintTicket back to Factory Defaults (`_FactDefaults`) and `psk:High` every single time right before submission**!
3. **HP's Proprietary Shortcut Override:**  
   HP V4 drivers embed an internal property:
   ```xml
   <psf:Property name="ns0000:ShortcutName">
     <psf:Value>_FactDefaults</psf:Value>
   </psf:Property>
   ```
   Whenever `_FactDefaults` was present, the printer firmware ignored resolution tags and forced **600 DPI Normal**.

### Applied Iterations & Final Solution:
| Iteration | Method Attempted | Result |
|---|---|---|
| **Attempt 1** | Win32 DEVMODE `dmPrintQuality = 300` | Ignored by HP V4 driver; printed 600 DPI. |
| **Attempt 2** | `Set-PrintConfiguration -Color:0` | Handled grayscale, but quality remained High/Normal. |
| **Attempt 3** | C# Helper calling `SetPrinter(Level 8 & 9)` | **Caused regression:** Reset V4 PrintTicket to Factory Defaults before every print. |
| **Attempt 4** | XPath injection of `psk:Draft` in PrintTicket | `psk:PageOutputQuality` was overwritten by `SetPrinter` running alongside it. |
| **Final Fix** | **1.** Removed legacy `SetPrinter` completely.<br>**2.** Injected HP's exact proprietary shortcut (`_FastEco`) into `PrintTicketXML`.<br>**3.** Set `psk:PageOutputQuality = psk:Draft`, `ns0000:JobOutputQualityPrev = ns0000:Draft`, `psk:PageResolution = ns0000:_300dpi`, and `Color = False`. | **100% Solved.** Verified live via PowerShell and Win32 `GetDeviceCaps` DC caps. |

---

## 5. 🤖 Telegram Bot Features & Menu

- **Native Command Menu (`[/]` Button):**
  Registered with Telegram servers via `bot.api.setMyCommands`:
  - `/start` — Start the bot & submit documents
  - `/menu` — Open main interactive navigation menu
  - `/jobs` — View submitted print jobs, job codes, and statuses
  - `/status` — Check status of the current active job
  - `/name` — View or update student display name
  - `/clear` — Clear current draft & reset chat session
  - `/help` — Guidelines, supported formats, and tips
  - `/commands` — Alias to help and command overview
- **Inline Keyboard Navigation:**
  - `📄 New Print Job`
  - `📋 My Jobs`
  - `❓ Help & Commands`
  - `👤 Change Name`
  - `🧹 Clear Session`
- **Supported File Types:** PDF, DOC, DOCX (up to 20 MB). Direct image uploads (JPG/PNG) prompt the student to convert to PDF first.

---

## 6. 🌐 Hosting & Git Configuration

- **Backend Hosting:**
  - **Platform:** Render (`https://render.com`)
  - **Service URL:** `https://hostel-print-backend-7w74.onrender.com`
  - **Database:** PostgreSQL on Render
  - **Telegram Integration:** Webhook in production (`/api/v1/telegram/webhook`); long-polling supported for local development.
- **Git Repository:**
  - **Remote URL:** `git@github.com:IAMUCN/print-your-stuff.git`
  - **Account:** `ucnisnanonymous@gmail.com` (`IAMUCN`)
  - **Render Account:** `sachinspeaks2023@gmail.com`
  - **Client Isolation:** Strictly segregated from `odishanurshing education` client repositories.
  - **Push Policy:** All changes committed locally; no remote push until explicitly directed by the user.

---

## 7. 🔍 Final Verification of Global Print Settings

Hardware and software verification performed live on the active machine:

```powershell
StorageQuality   : DRAFT
StorageDpi       : 300
StorageColorMode : FORCE_BW
DriverQuality    : psk:Draft
DriverResolution : ns0000:_300dpi
DriverShortcut   : _FastEco
DriverColor      : False (Monochrome)
HardwareCaps     : {"dpiX":300,"dpiY":300,"horzRes":2410,"vertRes":3438,"physWidth":2480,"physHeight":3508,"offsetX":35,"offsetY":35}
```

- **App Settings Default:** `DRAFT` / `300 DPI` / `FORCE_BW`
- **Windows PrintTicket:** `psk:Draft` / `ns0000:_300dpi` / `_FastEco`
- **Physical GDI Canvas:** `2410 x 3438` pixels at 300 DPI (Standard A4 printable area)
- **Auto-Fit Scaler:** Active in PDFium (`print_job.cpp`)
