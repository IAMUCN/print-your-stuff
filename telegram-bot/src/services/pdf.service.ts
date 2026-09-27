import { PDFDocument, PageSizes } from "pdf-lib";

export class PdfService {
  /**
   * Reads page count directly from a PDF buffer in-memory (<20MB RAM)
   */
  static async getPdfPageCount(buffer: Uint8Array): Promise<number> {
    try {
      const pdfDoc = await PDFDocument.load(buffer, { ignoreEncryption: true });
      return pdfDoc.getPageCount();
    } catch (error) {
      console.error("Failed to parse PDF page count:", error);
      return 1;
    }
  }

  /**
   * Composes 1 or multiple images into a standard A4 PDF document
   * Handles 1-per-page or 2-per-page grid layouts with preserved aspect ratios.
   */
  static async composeImagesToPdf(
    images: Array<{ buffer: Uint8Array; mimeType: string }>,
    layout: "ONE_PER_PAGE" | "TWO_PER_PAGE" | "FIT" | "ORIGINAL" = "FIT",
    orientation: "PORTRAIT" | "LANDSCAPE" | "AUTO" = "PORTRAIT"
  ): Promise<Uint8Array> {
    const pdfDoc = await PDFDocument.create();
    const isLandscape = orientation === "LANDSCAPE";
    const pageWidth = isLandscape ? PageSizes.A4[1] : PageSizes.A4[0];
    const pageHeight = isLandscape ? PageSizes.A4[0] : PageSizes.A4[1];
    const pageSize: [number, number] = [pageWidth, pageHeight];
    const margin = 36; // 0.5 inch margin

    // Helper: Safely embed PNG or JPG using magic bytes with fallback
    async function embedImageSafely(imgData: { buffer: Uint8Array; mimeType: string }) {
      const buf = imgData.buffer;
      const isPng = buf.length > 4 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47;

      if (isPng || imgData.mimeType.toLowerCase().includes("png")) {
        try {
          return await pdfDoc.embedPng(buf);
        } catch {
          return await pdfDoc.embedJpg(buf);
        }
      } else {
        try {
          return await pdfDoc.embedJpg(buf);
        } catch {
          return await pdfDoc.embedPng(buf);
        }
      }
    }

    if (layout === "TWO_PER_PAGE") {
      if (isLandscape) {
        // Landscape: 2 images placed side by side (horizontally)
        for (let i = 0; i < images.length; i += 2) {
          const page = pdfDoc.addPage(pageSize);
          const slotWidth = (pageWidth - margin * 3) / 2;
          const slotHeight = pageHeight - margin * 2;

          // Image 1 (Left slot)
          const img1 = await embedImageSafely(images[i]);
          const img1Dims = img1.scaleToFit(slotWidth, slotHeight);
          const img1X = margin + (slotWidth - img1Dims.width) / 2;
          const img1Y = margin + (slotHeight - img1Dims.height) / 2;
          page.drawImage(img1, {
            x: img1X,
            y: img1Y,
            width: img1Dims.width,
            height: img1Dims.height,
          });

          // Image 2 (Right slot, if present)
          if (i + 1 < images.length) {
            const img2 = await embedImageSafely(images[i + 1]);
            const img2Dims = img2.scaleToFit(slotWidth, slotHeight);
            const img2X = margin * 2 + slotWidth + (slotWidth - img2Dims.width) / 2;
            const img2Y = margin + (slotHeight - img2Dims.height) / 2;
            page.drawImage(img2, {
              x: img2X,
              y: img2Y,
              width: img2Dims.width,
              height: img2Dims.height,
            });
          }
        }
      } else {
        // Portrait: 2 images stacked vertically
        for (let i = 0; i < images.length; i += 2) {
          const page = pdfDoc.addPage(pageSize);
          const slotHeight = (pageHeight - margin * 3) / 2;
          const slotWidth = pageWidth - margin * 2;

          // Image 1 (Top slot)
          const img1 = await embedImageSafely(images[i]);
          const img1Dims = img1.scaleToFit(slotWidth, slotHeight);
          const img1X = margin + (slotWidth - img1Dims.width) / 2;
          const img1Y = margin * 2 + slotHeight + (slotHeight - img1Dims.height) / 2;
          page.drawImage(img1, {
            x: img1X,
            y: img1Y,
            width: img1Dims.width,
            height: img1Dims.height,
          });

          // Image 2 (Bottom slot, if present)
          if (i + 1 < images.length) {
            const img2 = await embedImageSafely(images[i + 1]);
            const img2Dims = img2.scaleToFit(slotWidth, slotHeight);
            const img2X = margin + (slotWidth - img2Dims.width) / 2;
            const img2Y = margin + (slotHeight - img2Dims.height) / 2;
            page.drawImage(img2, {
              x: img2X,
              y: img2Y,
              width: img2Dims.width,
              height: img2Dims.height,
            });
          }
        }
      }
    } else {
      // 1 image per page (default)
      for (const imgData of images) {
        const page = pdfDoc.addPage(pageSize);
        const printableWidth = pageWidth - margin * 2;
        const printableHeight = pageHeight - margin * 2;

        const img = await embedImageSafely(imgData);
        const dims = img.scaleToFit(printableWidth, printableHeight);
        const x = margin + (printableWidth - dims.width) / 2;
        const y = margin + (printableHeight - dims.height) / 2;

        page.drawImage(img, {
          x,
          y,
          width: dims.width,
          height: dims.height,
        });
      }
    }

    return await pdfDoc.save();
  }
}
