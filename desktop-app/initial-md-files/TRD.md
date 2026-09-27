# Hostel Print Automation — Desktop Admin App TRD

## 1. System Architecture & Components

```text
Flutter Desktop Client (Windows)
  |
  +-- Auth & Session Manager (JWT storage in Windows Credential Manager / encrypted storage)
  +-- Cloud API Client (HTTP client talking to Fastify backend on Render)
  +-- Queue Polling Engine (5-10s timer + manual trigger)
  +-- Local File & Cache Manager (Temporary cache in %TEMP%\hostel_print\)
  +-- Document Preview Engine (In-app vector PDF viewer)
  +-- LibreOffice Headless Subprocess Manager (DOC/DOCX -> PDF converter)
  +-- Printer Adapter Engine
        |
        +---> Windows Print Spooler (via Flutter 'printing' package)
        +---> Local Network Heartbeat (ICMP Ping / TCP Port 9100 / SNMP check)
```

## 2. Cloud Communication & File Ingestion
- **Authentication**: Admin sends `POST /api/v1/auth/login` and retains JWT access token.
- **Queue Synchronization**: Periodic `GET /api/v1/jobs/queue` poll every 5–10 seconds.
- **File Retrieval**:
  - The desktop client requests `GET /api/v1/jobs/:id/files/:fileId/stream`.
  - The backend proxies the file from Telegram to the desktop app.
  - The desktop app stores the file temporarily in `%TEMP%\hostel_print\<job_id>\`.
  - Temporary files are purged upon successful print or when the job is closed.

## 3. Local Document Conversion Engine (LibreOffice CLI)
When a job contains `.doc` or `.docx` files:
1. **Config Check**: Inspect local settings key `ask_approval_before_conversion` (default: `true`).
2. **Approval Gate**:
   - If `true`: Trigger an interactive approval modal on the UI: *"LibreOffice conversion required for <file>. Proceed?"*
   - If admin confirms (or if toggle is `false`): Transition file state to `CONVERTING`.
3. **Execution**:
   - Spawn background process via Dart `Process.start`:
     ```cmd
     soffice.exe --headless --convert-to pdf --outdir "%TEMP%\hostel_print\<job_id>\" "<input_path>"
     ```
   - Publish live conversion state to UI state manager (dashboard displays progress banner).
4. **Completion**:
   - Locate generated `.pdf`.
   - Update job view with converted PDF for preview and printing.
   - Clean up source `.docx` and temporary artifacts.

## 4. Printer Adapter Architecture
The application uses an abstract `PrinterAdapter` layer to decouple UI logic from OS printing APIs:

```dart
abstract class PrinterAdapter {
  Future<PrinterStatus> getStatus(String printerName, String? ipAddress);
  Future<bool> printDocument({
    required File document,
    required PrintSettings settings,
    required String targetPrinter,
  });
}
```

### Implementation Details:
- **Print Execution**: Uses the Flutter `printing` package (`Printing.directPrintPdf`), routing directly to the installed Windows print driver for the **HP Smart Tank 589**.
- **Printer Status Monitoring**:
  - Periodic local heartbeat: Sends lightweight TCP check to printer's RAW port (`9100`) or ICMP ping to verify Wi-Fi reachability.
  - Queries Windows Print Spooler queue flags for paper jam, out of paper, or offline states.
  - Updates the top-bar status chip (`ONLINE`, `OFFLINE`, `PRINTING`).

## 5. Security & Isolation
- **Zero Secrets Shipped**: No Telegram Bot token, no Supabase database connection string, and no master password exist inside the desktop client binary.
- **Session Tokens**: JWT stored using encrypted Windows DPAPI (via `flutter_secure_storage`).
- **TLS Validation**: Strict HTTPS certificate verification enabled for all cloud calls.
