# UI/UX Specification — Desktop Admin App (Flutter Desktop)

## Visual Direction & Palette
- **Monochrome & High Contrast**: Built on Material 3 principles using a pure black, dark charcoal, and white palette.
- **Visual Hierarchy**: Clear typography and strong contrast between primary actions, job codes, and secondary metadata.
- **Resource Consciousness**: Subtle, visible progress indicators so the admin on a lower-spec machine always knows when local background tasks (like LibreOffice) are executing.

### Color Tokens
```text
Background:       #121212 (Near Black)
Surface:          #1E1E1E (Dark Charcoal)
Surface Elevated: #2A2A2A (Card / Modal Surface)
Primary:          #FFFFFF (White)
Secondary:        #B0B0B0 (Light Gray)
Border / Divider: #383838 (Subtle Gray)
Status Active:    #FFFFFF (High contrast outlined or filled badge)
```

---

## Screen Wireframes

### 1. Main Dashboard & Queue
```text
┌────────────────────────────────────────────────────────────────────────┐
│  HOSTEL PRINT MANAGER      [ Search #Code / Name ]   [⟳ Refresh]  ● ONLINE│
├───────────────────┬────────────────────────────────────────────────────┤
│ ACTIVE QUEUE (3)  │ JOB DETAILS                                        │
│                   │                                                    │
│ > #1047   WAITING │ Job #1047 · Rahul Sharma                           │
│   Rahul Sharma    │ Submitted 12m ago · 2 files · Est. 17 sheets       │
│   2 files · 17 sh │                                                    │
│                   │ ────────────────────────────────────────────────── │
│   #1048   WAITING │ 📄 assignment.pdf (8 pages · 1.2 MB)               │
│   Priya Patel     │    B&W · 2 copies · Pages 1-8 · 1/sheet            │
│   1 file · 4 sh   │    [ 👁️ Preview ]  [ 💾 Download ]  [ ✏️ Edit ]     │
│                   │                                                    │
│   #1049   WAITING │ 📄 syllabus.docx (340 KB)                          │
│   Amit Kumar      │    B&W · 1 copy · 1/sheet                          │
│   1 file · ? sh   │    [ ⚙️ Convert to PDF ]  [ 💾 Download ]           │
│                   │                                                    │
│                   │ ────────────────────────────────────────────────── │
│                   │                                                    │
│                   │ [ ❌ Cancel Job ]                   [ 🖨️ PRINT JOB ]│
└───────────────────┴────────────────────────────────────────────────────┘
```

---

### 2. Live Conversion Banner (Resource Awareness)
Displayed across the top of the job details or dashboard when LibreOffice is actively running:

```text
┌────────────────────────────────────────────────────────────────────────┐
│ ⚙️ LibreOffice is converting "syllabus.docx" to PDF... Please wait.   │
└────────────────────────────────────────────────────────────────────────┘
```

---

### 3. LibreOffice Conversion Approval Modal
Triggered before launching the background process when the approval toggle is enabled:

```text
┌──────────────────────────────────────────────────────────┐
│  Convert Document to PDF?                                │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  "syllabus.docx" requires LibreOffice to convert it      │
│  into a printable PDF.                                   │
│                                                          │
│  This may temporarily use CPU & memory on your laptop.   │
│                                                          │
│  Do you want to proceed with conversion?                 │
│                                                          │
│                 [ Cancel ]    [ Approve & Convert ]      │
└──────────────────────────────────────────────────────────┘
```

---

### 4. Settings View
```text
┌──────────────────────────────────────────────────────────┐
│  SETTINGS                                                │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  PRINTER CONFIGURATION                                   │
│  Target Printer:  [ HP Smart Tank 589 Series      ▼ ]    │
│  Printer IP:      [ 192.168.1.150                 ]      │
│  Connection:      ● Online (Spooler Ready & Ping OK)     │
│                                                          │
│  DOCUMENT CONVERSION                                     │
│  Ask for approval before converting Docs to PDF:  [ ON ] │
│  LibreOffice Path: [ C:\Program Files\LibreOffice\program]│
│                                                          │
│  QUEUE & SYNC                                            │
│  Auto-polling Interval: [ 5 seconds              ▼ ]     │
│                                                          │
│  [ Save Settings ]                                       │
└──────────────────────────────────────────────────────────┘
```
