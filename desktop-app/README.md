# Hostel Print Admin — Desktop Workstation (Windows)

A high-contrast, Material 3 monochrome desktop application built with Flutter Desktop for Windows. Designed specifically for hostel print management workstations running with an **HP Smart Tank 589** printer.

---

## Key Capabilities

- **Live Print Queue**: Auto-polling every 5 seconds (configurable) with an instant manual `[⟳ Refresh]` button.
- **Search & Quick Lookup**: Instant filtering by sequential Job Code (e.g. `#1047`) or student name.
- **Job & File Inspection**: Detailed file breakdown, calculated output sheets, and per-file settings (copies, B&W/color, page ranges).
- **In-App PDF Preview**: Direct high-fidelity PDF viewing with zoom, page navigation, and download actions.
- **HP Smart Tank 589 Integration**:
  - Direct print dispatch through the Windows Print Spooler (`printing` package).
  - Live network heartbeat checking printer reachability (`ONLINE` / `OFFLINE`).
- **LibreOffice DOCX Conversion Safeguards**:
  - Automatically or manually converts Word documents to PDF using headless LibreOffice.
  - **Approval Toggle**: *"Ask approval before converting Docs to PDF"* (enabled by default) prompts the admin before launching LibreOffice to protect weaker laptops from CPU/RAM spikes.
  - **Live Banner**: Shows a real-time progress banner on the dashboard whenever LibreOffice is actively converting files.

---

## Getting Started

### 1. Requirements
- Windows 10/11
- Flutter SDK 3.35+ (Dart 3.9+)
- Visual Studio 2022 with "Desktop development with C++" workload installed
- (Optional, for DOCX conversion): [LibreOffice](https://www.libreoffice.org/download/download/) installed at `C:\Program Files\LibreOffice\program\soffice.exe`

### 2. Run in Development Mode
```powershell
# From the desktop-app directory:
flutter run -d windows
```

### 3. Build Release Windows Executable
```powershell
flutter build windows --release
```
The compiled standalone executable and support files will be in:
`build\windows\x64\runner\Release\`

---

## Configuration & First Login

1. When opening the app, you will see the **Admin Workstation Login** screen.
2. Click the ⚙️ Settings icon in the top right to configure:
   - **Backend REST API URL**: `http://localhost:3000` (for local development) or your deployed Render URL (e.g. `https://hostel-print-backend.onrender.com`).
   - **Target Windows Printer**: Select your installed HP Smart Tank 589 driver from the dropdown.
   - **Printer Local IP**: Enter your printer's local Wi-Fi IP (e.g. `192.168.1.150`) to enable live Online/Offline status detection.
   - **Ask approval before converting Docs to PDF**: Toggle ON (default) or OFF.
   - **LibreOffice Executable Path**: Path to `soffice.exe`.
3. Default credentials (seeded automatically by the backend):
   - **Username**: `admin`
   - **Password**: `adminpassword123` (or whatever was set in backend `.env`)
