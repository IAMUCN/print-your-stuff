# UI/UX Specification — Telegram Bot

## Design Principles
- **Minimal Conversational Overhead**: Use inline keyboards for all interactive decisions; never require users to type obscure slash commands for settings.
- **Immediate Context**: Always show the current list of staged files and active settings in the message body.
- **Frictionless Onboarding**: Single prompt for display name on first visit; no unnecessary phone or student ID prompts.
- **Clarity Over Jargon**: Clear labels for B&W vs Color, Copies, and Page Ranges.

---

## Screen & Message Wireframes

### 1. Main Menu
```text
Hostel Print Service
Welcome, Alex!

Submit your files below to get a print job code.

[ 📄 New Print Job ]
[ 📋 My Jobs ]
[ ❓ Help & Formats ]
```

---

### 2. Upload State (Draft)
```text
PRINT JOB DRAFT
Files added (2):

1. assignment.pdf (8 pages · 1.2 MB)
2. syllabus.docx (340 KB)
   ⚠️ Note: DOCX files are converted on the admin station.

[ ⚙️ Configure Files ]
[ ➕ Add More Files ]
[ 🏁 Review & Submit ]
[ ❌ Cancel ]
```

---

### 3. File Settings Dialog (Inline Keyboard)
```text
Configuring: assignment.pdf (8 pages)

Pages:
[ All (1-8) ]  [ 1-5 ]  [ Custom ]

Copies:
[ ➖ ]  1  [ ➕ ]

Color Mode:
[ 🔘 Black & White ]  [ ⚪ Color ]

Pages Per Sheet:
[ 🔘 1 / Sheet ]  [ ⚪ 2 / Sheet ]

[ 💾 Save Settings ]  [ ⬅️ Back ]
```

---

### 4. Image Group Configuration
```text
Configuring Photos (2 images)

Layout:
[ 🔘 2 Images / Page (Grid) ]  [ ⚪ 1 Image / Page ]

Color Mode:
[ 🔘 Color ]  [ ⚪ Black & White ]

Orientation:
[ 🔘 Portrait ]  [ ⚪ Landscape ]

[ 💾 Save Settings ]  [ ⬅️ Back ]
```

---

### 5. Final Summary & Submission
```text
PRINT JOB SUMMARY

1. assignment.pdf
   Pages 1-8 · 2 copies · Black & White · 1/sheet
   Est. Sheets: 16

2. id_card_front.jpg + id_card_back.jpg
   2/page grid · 1 copy · Color
   Est. Sheets: 1

Total Estimated Sheets: 17

[ 🚀 SUBMIT PRINT JOB ]
[ ✏️ Edit Settings ]
[ ❌ Cancel ]
```

---

### 6. Job Confirmation & In-Person Instructions
```text
✅ Print Job Submitted!

Job Code: #1047
Status: WAITING FOR APPROVAL

Please visit the hostel admin's room and share your code #1047 to get your documents printed.

Note: Unprinted jobs expire automatically after 48 hours.

[ 📋 View in My Jobs ]  [ 🏠 Main Menu ]
```
