# User Flow — Telegram Bot

## Student Workflow

```text
/start
  |
  +-- First-time visitor? --> Prompt for Display Name (Name only)
  |
  v
Main Menu
  |
  +-- [ New Print Job ]
  |      |
  |      v
  |   Send Document or Photo (up to 20 MB)
  |      |
  |      +--> (PDF): Cloud parses page count in-memory
  |      +--> (DOC/DOCX): Noted for desktop conversion
  |      +--> (Image): Added to photo draft
  |      |
  |      +-- [ Add More Files ] (repeat upload)
  |      |
  |      v
  |   Configure Print Settings
  |      |
  |      +-- Configure individual file (Copies, B&W/Color, Page Range, Image Layout)
  |      +-- Bulk configure all files
  |      |
  |      v
  |   [ Finish / Review ]
  |      |
  |      v
  |   Complete Job Summary Displayed
  |      |
  |      +-- [ Edit Settings ]
  |      +-- [ Cancel Job ]
  |      |
  |      v
  |   [ SUBMIT JOB ]
  |      |
  |      v
  |   Job Code Issued: #1047
  |   Status: WAITING
  |   Instructions: "Visit the hostel admin's room with code #1047 for printing."
  |
  +-- [ My Jobs ]
  |      |
  |      v
  |   List active & past submissions (with Status & Job Codes)
  |   Options to cancel active WAITING jobs
  |
  +-- [ Help ]
         |
         v
      Guidelines on supported formats (PDF, JPG, PNG, DOCX) and pricing/pickup info
```

## Physical In-Person Print Protocol
1. Student receives their Job Code (e.g. `#1047`) in the bot.
2. Student comes in person to the hostel admin's room.
3. Student quotes `#1047` to the admin.
4. Admin reviews the files and settings on the Desktop Admin App, approves them, and triggers the print.
5. Student collects physical sheets immediately.
6. The chat remains quiet: no push notification spam is sent to Telegram during printing or completion.
