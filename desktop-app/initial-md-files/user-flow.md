# User Flow — Desktop Admin App

## 1. Application Launch & Authentication

```text
Launch App
   |
   v
Login Screen (Username & Password)
   |
   +--> [ Authenticate with Render Fastify Backend ]
   |
   v (Success)
Dashboard View
   |
   +--> Initial Queue Fetch (GET /api/v1/jobs/queue)
   +--> Start 5-10s Background Polling
   +--> Check HP Smart Tank 589 Spooler & Network Status
```

---

## 2. In-Person Print Processing Flow

```text
Student walks into the room: "My code is #1047"
   |
   v
Admin Enters "1047" in Search / Clicks #1047 in Queue
   |
   v
Job Detail Panel Loads
   |
   +-- Files checked:
   |
   +-- If file is PDF or Image Group:
   |      |
   |      v
   |   Ready immediately for Preview / Print
   |
   +-- If file is DOC / DOCX:
          |
          v
       Is "Ask for approval before conversion" ENABLED?
          |
          +-- [YES (Default)] --> Show Approval Dialog:
          |                       "LibreOffice needs to convert 'notes.docx' to PDF.
          |                        Do you accept?"
          |                           |
          |                           +--> [Cancel] -> Skip conversion
          |                           |
          |                           +--> [Approve] -> Launch LibreOffice
          |
          +-- [NO] -------------> Launch LibreOffice directly
          |
          v
       Dashboard Displays Live Banner:
       "⚙️ Converting notes.docx via LibreOffice..."
          |
          v
       Conversion Completes -> PDF ready for Preview & Print
```

---

## 3. Print Execution & Completion Flow

```text
Admin Reviews Files & Print Settings (Copies, B&W/Color)
   |
   +-- (Optional) Admin clicks [Edit] to adjust settings
   +-- (Optional) Admin clicks [Preview] to inspect pages
   |
   v
Admin Clicks [ PRINT JOB ]
   |
   v
Confirmation Modal:
"Print Job #1047 (Rahul Sharma)
 2 files · 17 estimated sheets
 Target Printer: HP Smart Tank 589 (ONLINE)"
   |
   v
[ CONFIRM PRINT ]
   |
   +--> Dispatches PDF to Windows Print Spooler
   +--> Backend transitions job status to PRINTED
   |
   v
Print Complete Banner
Admin hands printed pages to student.
```
