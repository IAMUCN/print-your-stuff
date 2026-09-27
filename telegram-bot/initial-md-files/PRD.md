# Hostel Print Automation — Telegram Bot PRD

## 1. Purpose
The Telegram bot is the student-facing interface for submitting and configuring print jobs in a hostel environment.

The bot accepts supported files, collects predefined print settings, creates a final job summary, and submits the job to the cloud backend. It generates a sequential numeric Job Code (e.g. `#1047`). It never directly triggers printing; printing is executed in-person by the hostel administrator at the print station.

## 2. Goals
- Let students submit print jobs quickly via Telegram without needing a website or app installation.
- Support multi-file print submissions.
- Allow per-file configuration (copies, B&W/color, page range, image layout).
- Generate a short, easily-communicable sequential Job Code (starting at `#1001`).
- Keep printing behind explicit in-person administrator authorization.
- Prevent chat notification spam: In V1, status updates are pull-only via `My Jobs` since students visit the admin's room in person for print approval.
- Support graceful submission 24/7 even while the admin desktop app is offline.

## 3. Supported Inputs & File Processing
- **PDF**: Primary document format. Cloud backend parses page count immediately upon upload to validate page ranges.
- **Images (JPG, PNG, WebP)**: Supported individually or as a photo group. Composed into print-ready A4 PDF layouts on-demand.
- **Documents (DOC, DOCX)**: Accepted and queued. For V1, page count is verified and converted locally on the admin print workstation (to protect cloud free-tier memory). Students are informed that PDF is recommended for instant page validation.

**Upload limits**: Maximum 20 MB per file (enforced by Telegram Bot API).

## 4. PDF Print Settings
- **Page range**: All, or custom range (e.g. `1-5`, `3,7,9-12`). Validated against parsed total pages.
- **Copies**: Positive integer (default: 1).
- **Color Mode**: Black & White (default) or Color.
- **Single-sided only**: Duplex is out of scope for V1.
- **Pages per sheet**: 1 (default) or 2.

## 5. Image Settings
- **Layout**: 1 image/page or 2 images/page (grid composition).
- **Fitting**: Fit to printable area while preserving aspect ratio.
- **Copies**: Positive integer (default: 1).
- **Color Mode**: Color (default) or Black & White.
- **Orientation**: Portrait or Landscape.

## 6. Student Workflow
1. `/start`
2. **First-time Registration**: Asks for the student's display name only (frictionless onboarding).
3. **Main Menu**: Student selects `New Print Job`.
4. **Upload Files**: Student uploads documents/images.
5. **Configuration**: Student configures files individually or via bulk settings.
6. **Job Summary**: Bot displays full breakdown of files, settings, and calculated page totals.
7. **Submission**: Student taps `[SUBMIT JOB]`.
8. **Job Code Issued**: Backend assigns a sequential Job Code (e.g. `#1047`).
9. **In-Person Pickup**: Student visits the hostel admin's room and provides their Job Code for print approval.
10. **Status Check**: Student can check job progress or past prints anytime using `My Jobs`.

## 7. Security & Privacy
- Telegram numeric user ID is the immutable identity key.
- Students cannot execute or trigger print operations.
- Admin credentials and Telegram bot tokens are never exposed.
- No public file URLs are exposed.
- Admin authorization is strictly separated from student roles.

## 8. Retention & Expiration
- **Pending (WAITING) Jobs**: Expire automatically after **24–48 hours** if uncollected, preventing queue congestion.
- **Completed (PRINTED) Jobs**: Retained in database history for **7 days** before archival.
- **Telegram File References**: Expired jobs are marked in PostgreSQL and their files are no longer served to the desktop workstation.

## 9. Scope Boundaries (V1 vs Future)
- **V1 (In Scope)**:
  - Telegram bot submission and configuration.
  - Sequential job codes.
  - Smart hybrid file processing (PDF/images on cloud, DOCX on desktop).
  - In-person collection workflow.
- **V2 / V3 (Deferred)**:
  - Automated push notifications on print progress ("Printing started", "Ready for pickup").
  - Digital payments integration.
  - Duplex (double-sided) printing.
  - Mobile admin application.
