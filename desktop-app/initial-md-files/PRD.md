# Hostel Print Automation — Desktop Admin App PRD

## 1. Purpose
The Desktop Application is the hostel administrator's local print workstation running on Windows. It connects to the Cloud Backend, displays the live print queue, retrieves files through authenticated endpoints, previews/edits jobs, converts DOC/DOCX files locally, and executes printing to the HP Smart Tank 589 via the Windows Print Spooler.

## 2. Core Architecture Principle
The desktop app is a client workstation, not the system of record. PostgreSQL (Supabase) remains authoritative for all job states, settings, and lifecycle transitions.

## 3. Technology & Target Platform
- **Platform**: Windows 10/11 Desktop
- **Framework**: Flutter Desktop (Windows)
- **UI Design**: Material 3 monochrome / high-contrast dark theme
- **Printing Pipeline**: Windows Print Spooler via Flutter `printing` package + local network heartbeat for HP Smart Tank 589 status.

## 4. Key Workstation Capabilities
- **Admin Authentication**: Username and password login backed by bcrypt verification and JWT session tokens.
- **Live Queue Monitoring**: Automatic interval polling (every 5–10s) with an immediate manual `[Refresh]` action.
- **Search & Filter**: Instant lookup by sequential Job Code (`#1047`) or student display name.
- **Job Detail & Inspection**: Full view of submitted files, page counts, B&W/color mode, copies, and estimated sheet counts.
- **In-App Document Preview**: Integrated preview for PDFs and composed image grids with page navigation and zoom.
- **Print Settings Adjustment**: Admin can modify copies, page ranges, or color modes on the fly before dispatching to the printer.
- **Physical Print Execution**: One-click print dispatch to the installed HP Smart Tank 589 driver.
- **Printer Status Indicator**: Live persistent indicator (`ONLINE` / `OFFLINE` / `PRINTING`) backed by Windows spooler state and local network ping.

## 5. Local Document Conversion (LibreOffice Integration)
To keep the cloud backend lightweight and avoid cloud OOM crashes, DOC/DOCX files are converted locally on the admin PC using headless LibreOffice (`soffice.exe`):
- **Resource Protection for Lower-Spec PCs**:
  - The admin's machine may have limited CPU/RAM. The app must never freeze or invisibly spike system resources.
- **Approval Safeguard (Settings Toggle)**:
  - Settings includes a toggle: *"Ask for approval before converting Docs to PDF"* (Default: **Enabled**).
  - When enabled, the app prompts the admin before launching LibreOffice: *"LibreOffice needs to convert '<filename>.docx' to PDF. Do you accept?"*
  - When disabled, conversion runs automatically upon file inspection.
- **Live UI Feedback**:
  - Whenever LibreOffice is converting a file, a clear visual status banner/spinner appears on the dashboard and job card: *"⚙️ Converting <filename> via LibreOffice..."* so the administrator is always aware of active background workloads.

## 6. Offline & Reconnection Behavior
- If the printer is offline: The desktop displays `Printer: OFFLINE`. Print actions are disabled with clear guidance; existing queue items remain safely queued in the cloud.
- If network connection drops: The app transitions gracefully to an offline state, queuing UI actions and auto-reconnecting on the next poll.
- Stale queue management: Unprinted jobs expire automatically on the cloud backend after 24–48 hours, keeping the local queue clean.
