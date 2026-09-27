# Backend Schema — Desktop App Client View

The Desktop Admin App communicates with the shared Supabase PostgreSQL database exclusively through the authenticated Fastify REST API.

---

## 1. Queue Response Contract (`GET /api/v1/jobs/queue`)
Returns an ordered array of pending submissions (`WAITING` or `PRINTING`), ordered chronologically.

```json
[
  {
    "id": "c7a8b9f0-1234-5678-90ab-cdef12345678",
    "jobCode": 1047,
    "studentName": "Rahul Sharma",
    "status": "WAITING",
    "createdAt": "2026-09-26T01:30:00Z",
    "expiresAt": "2026-09-28T01:30:00Z",
    "fileCount": 2,
    "totalSheetsEst": 17,
    "files": [
      {
        "id": "f1-...",
        "filename": "assignment.pdf",
        "inputType": "PDF",
        "pageCount": 8,
        "sizeBytes": 1245184,
        "settings": {
          "pageRange": "1-8",
          "copies": 2,
          "colorMode": "BW",
          "pagesPerSheet": 1,
          "orientation": "PORTRAIT"
        }
      },
      {
        "id": "f2-...",
        "filename": "notes.docx",
        "inputType": "DOCX",
        "pageCount": null,
        "sizeBytes": 348160,
        "settings": {
          "pageRange": null,
          "copies": 1,
          "colorMode": "BW",
          "pagesPerSheet": 1,
          "orientation": "PORTRAIT"
        }
      }
    ]
  }
]
```

---

## 2. Job Detail Response Contract (`GET /api/v1/jobs/:id`)
Provides complete metadata, file list, settings, and prior print attempts.

```json
{
  "id": "c7a8b9f0-1234-5678-90ab-cdef12345678",
  "jobCode": 1047,
  "studentName": "Rahul Sharma",
  "status": "WAITING",
  "createdAt": "2026-09-26T01:30:00Z",
  "files": [ ... ],
  "attempts": [
    {
      "id": "att-1",
      "status": "FAILED",
      "startedAt": "2026-09-26T01:40:00Z",
      "errorMessage": "Printer spooler reported paper jam",
      "printerName": "HP Smart Tank 589"
    }
  ]
}
```

---

## 3. Settings Mutation (`PATCH /api/v1/jobs/:id/settings`)
Allows the administrator to adjust print settings before printing.

```json
{
  "fileId": "f1-...",
  "settings": {
    "pageRange": "1-5",
    "copies": 3,
    "colorMode": "COLOR"
  }
}
```

---

## 4. Status Transition Mutation (`POST /api/v1/jobs/:id/status`)
Dispatches job state transitions.

```json
{
  "status": "PRINTED",
  "printerName": "HP Smart Tank 589",
  "errorMessage": null
}
```
