import { FastifyInstance } from "fastify";
import { db, schema } from "../../db/index.js";
import { eq, inArray, desc, asc, and } from "drizzle-orm";
import { TelegramFileService } from "../../services/telegram-file.service.js";
import { PdfService } from "../../services/pdf.service.js";

export async function jobsRoutes(fastify: FastifyInstance, options?: { bot?: any }) {
  // Pre-handler hook to authenticate admin JWT
  fastify.addHook("preHandler", async (request, reply) => {
    try {
      await request.jwtVerify();
    } catch (err) {
      return reply.status(401).send({ error: "Unauthorized admin request" });
    }
  });

  // 1. Get Live Print Queue
  fastify.get("/queue", async () => {
    const queueJobs = await db.query.jobs.findMany({
      where: inArray(schema.jobs.status, ["WAITING", "PRINTING"]),
      orderBy: [asc(schema.jobs.createdAt)],
      with: {
        user: true,
        files: {
          with: { settings: true },
          orderBy: [asc(schema.jobFiles.sortOrder)],
        },
      },
    });

    return queueJobs.map((job) => {
      // Calculate estimated total sheets
      let totalSheets = 0;
      for (const file of job.files) {
        const copies = file.settings?.copies || 1;
        const pages = file.pageCount || 1;
        const pps = file.settings?.pagesPerSheet || 1;
        const sheetsPerCopy = Math.ceil(pages / pps);
        totalSheets += sheetsPerCopy * copies;
      }

      return {
        id: job.id,
        jobCode: job.jobCode,
        studentName: job.user.displayName,
        status: job.status,
        createdAt: job.createdAt,
        expiresAt: job.expiresAt,
        fileCount: job.files.length,
        totalSheetsEst: totalSheets,
        files: job.files.map((f) => ({
          id: f.id,
          filename: f.originalFilename,
          inputType: f.inputType,
          pageCount: f.pageCount,
          sizeBytes: f.sizeBytes,
          status: f.status || "PENDING",
          errorMessage: f.errorMessage || null,
          printedAt: f.printedAt || null,
          settings: f.settings
            ? {
                pageRange: f.settings.pageRange,
                copies: f.settings.copies,
                colorMode: f.settings.colorMode,
                pagesPerSheet: f.settings.pagesPerSheet,
                orientation: f.settings.orientation,
                imageLayout: f.settings.imageLayout,
              }
            : null,
        })),
      };
    });
  });

  // 2. Get Job History (Past 7 days)
  fastify.get("/history", async () => {
    const historyJobs = await db.query.jobs.findMany({
      where: inArray(schema.jobs.status, [
        "PRINTED",
        "PARTIALLY_PRINTED",
        "FAILED",
        "CANCELLED",
      ]),
      orderBy: [desc(schema.jobs.updatedAt)],
      limit: 50,
      with: {
        user: true,
        files: { with: { settings: true } },
        attempts: true,
      },
    });

    return historyJobs.map((job) => {
      let totalSheets = 0;
      for (const file of job.files) {
        const copies = file.settings?.copies || 1;
        const pages = file.pageCount || 1;
        const pps = file.settings?.pagesPerSheet || 1;
        const sheetsPerCopy = Math.ceil(pages / pps);
        totalSheets += sheetsPerCopy * copies;
      }

      return {
        id: job.id,
        jobCode: job.jobCode,
        studentName: job.user.displayName,
        status: job.status,
        createdAt: job.createdAt,
        submittedAt: job.submittedAt,
        updatedAt: job.updatedAt,
        fileCount: job.files.length,
        totalSheetsEst: totalSheets,
        files: job.files.map((f) => ({
          id: f.id,
          filename: f.originalFilename,
          inputType: f.inputType,
          pageCount: f.pageCount,
          sizeBytes: f.sizeBytes,
          status: f.status || "PENDING",
          errorMessage: f.errorMessage || null,
          printedAt: f.printedAt || null,
          settings: f.settings
            ? {
                pageRange: f.settings.pageRange,
                copies: f.settings.copies,
                colorMode: f.settings.colorMode,
                pagesPerSheet: f.settings.pagesPerSheet,
                orientation: f.settings.orientation,
                imageLayout: f.settings.imageLayout,
              }
            : null,
        })),
        attempts: job.attempts,
      };
    });
  });

  // 3. Get Specific Job Details
  fastify.get("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };

    const job = await db.query.jobs.findFirst({
      where: eq(schema.jobs.id, id),
      with: {
        user: true,
        files: {
          with: { settings: true },
          orderBy: [asc(schema.jobFiles.sortOrder)],
        },
        attempts: {
          orderBy: [desc(schema.printAttempts.startedAt)],
        },
      },
    });

    if (!job) {
      return reply.status(404).send({ error: "Job not found" });
    }

    return job;
  });

  // 4. Update File Print Settings
  fastify.patch("/:id/settings", async (request, reply) => {
    const { fileId, settings } = request.body as {
      fileId: string;
      settings: {
        pageRange?: string;
        copies?: number;
        colorMode?: "COLOR" | "BW";
        pagesPerSheet?: number;
        orientation?: "PORTRAIT" | "LANDSCAPE" | "AUTO";
        imageLayout?: "ONE_PER_PAGE" | "TWO_PER_PAGE" | "FIT" | "ORIGINAL";
      };
    };

    if (!fileId || !settings) {
      return reply.status(400).send({ error: "fileId and settings are required" });
    }

    await db
      .update(schema.printSettings)
      .set(settings)
      .where(eq(schema.printSettings.jobFileId, fileId));

    return { success: true };
  });

  // 5. Update Job Status & Log Print Attempt
  fastify.post("/:id/status", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { status, printerName, errorMessage } = request.body as {
      status: "WAITING" | "PRINTING" | "PRINTED" | "PARTIALLY_PRINTED" | "FAILED" | "CANCELLED";
      printerName?: string;
      errorMessage?: string;
    };

    const admin = request.user as { id: string };

    const job = await db.query.jobs.findFirst({
      where: eq(schema.jobs.id, id),
      with: { user: true },
    });

    if (!job) {
      return reply.status(404).send({ error: "Job not found" });
    }

    await db
      .update(schema.jobs)
      .set({
        status,
        updatedAt: new Date(),
      })
      .where(eq(schema.jobs.id, id));

    if (status === "PRINTED") {
      await db
        .update(schema.jobFiles)
        .set({ status: "PRINTED", printedAt: new Date() })
        .where(eq(schema.jobFiles.jobId, id));
    }

    // If an attempt was executed, log it safely
    try {
      let adminId: string | undefined = admin?.id;
      if (adminId) {
        const userExists = await db.query.users.findFirst({
          where: eq(schema.users.id, adminId),
        });
        if (!userExists) {
          const fallbackAdmin = await db.query.users.findFirst({
            where: eq(schema.users.role, "ADMIN"),
          });
          adminId = fallbackAdmin?.id;
        }
      }

      const validAdminId = adminId;
      if (validAdminId && ["PRINTED", "PARTIALLY_PRINTED", "FAILED"].includes(status)) {
        await db.insert(schema.printAttempts).values({
          jobId: id,
          initiatedBy: validAdminId,
          status: status as any,
          completedAt: new Date(),
          errorMessage: errorMessage || null,
          printerName: printerName || "HP Smart Tank 580-590 series",
        });
      }

      if (validAdminId) {
        await db.insert(schema.jobEvents).values({
          jobId: id,
          eventType: `STATUS_CHANGED_TO_${status}`,
          metadata: { updatedBy: validAdminId, printerName, errorMessage },
        });
      }

      // Minimal Telegram notification: ONLY send on completed PRINTED status to save bandwidth
      if (options?.bot && job.user?.telegramUserId && status === "PRINTED") {
        try {
          await options.bot.api.sendMessage(
            job.user.telegramUserId,
            `Print job #${job.jobCode} printed.`
          );
        } catch (botNotifyErr) {
          request.log.warn(botNotifyErr, "Could not send Telegram notification to student");
        }
      }
    } catch (logErr) {
      request.log.warn(logErr, "Non-fatal error logging print attempt/event");
    }

    return { success: true, status };
  });

  // 6. Stream Original File from Telegram to Desktop
  fastify.get("/:id/files/:fileId/stream", async (request, reply) => {
    const { fileId } = request.params as { fileId: string };

    const file = await db.query.jobFiles.findFirst({
      where: eq(schema.jobFiles.id, fileId),
    });

    if (!file) {
      return reply.status(404).send({ error: "File not found" });
    }

    try {
      const buffer = await TelegramFileService.downloadFileBuffer(file.telegramFileId);

      reply.header("Content-Type", file.mimeType);
      reply.header(
        "Content-Disposition",
        `inline; filename="${encodeURIComponent(file.originalFilename)}"`
      );
      return reply.send(Buffer.from(buffer));
    } catch (error) {
      request.log.error(error);
      return reply.status(502).send({ error: "Failed to download file from Telegram" });
    }
  });

  // 7. On-Demand Composed PDF for Image Groups
  fastify.get("/:id/composed-pdf", async (request, reply) => {
    const { id } = request.params as { id: string };

    const job = await db.query.jobs.findFirst({
      where: eq(schema.jobs.id, id),
      with: {
        files: {
          with: { settings: true },
          orderBy: [asc(schema.jobFiles.sortOrder)],
        },
      },
    });

    if (!job) {
      return reply.status(404).send({ error: "Job not found" });
    }

    const imageFiles = job.files.filter((f) => f.inputType === "IMAGE");
    if (imageFiles.length === 0) {
      return reply.status(400).send({ error: "No image files found in this job" });
    }

    try {
      const images: Array<{ buffer: Uint8Array; mimeType: string }> = [];
      for (const imgFile of imageFiles) {
        const buf = await TelegramFileService.downloadFileBuffer(imgFile.telegramFileId);
        images.push({ buffer: buf, mimeType: imgFile.mimeType });
      }

      const isTwoPerPage = imageFiles.some((f) => f.settings?.imageLayout === "TWO_PER_PAGE");
      const layout = isTwoPerPage ? "TWO_PER_PAGE" : (imageFiles[0]?.settings?.imageLayout || "FIT");
      const isLandscape = imageFiles.some((f) => f.settings?.orientation === "LANDSCAPE");
      const orientation = isLandscape ? "LANDSCAPE" : (imageFiles[0]?.settings?.orientation || "PORTRAIT");
      const composedBuffer = await PdfService.composeImagesToPdf(images, layout, orientation);

      reply.header("Content-Type", "application/pdf");
      reply.header("Content-Disposition", `inline; filename="composed_job_${job.jobCode || id}.pdf"`);
      return reply.send(Buffer.from(composedBuffer));
    } catch (error) {
      request.log.error(error);
      return reply.status(500).send({ error: "Failed to compose images into PDF" });
    }
  });

  // 8. Update Individual File Status (PDF-level tracking)
  fastify.patch("/:id/files/:fileId/status", async (request, reply) => {
    const { id, fileId } = request.params as { id: string; fileId: string };
    const { status, errorMessage } = request.body as {
      status: "PENDING" | "PRINTING" | "PRINTED" | "FAILED";
      errorMessage?: string;
    };

    const file = await db.query.jobFiles.findFirst({
      where: and(eq(schema.jobFiles.id, fileId), eq(schema.jobFiles.jobId, id)),
    });

    if (!file) {
      return reply.status(404).send({ error: "File not found in job" });
    }

    const updated = await db
      .update(schema.jobFiles)
      .set({
        status: status || "PENDING",
        errorMessage: errorMessage || null,
        printedAt: status === "PRINTED" ? new Date() : undefined,
      })
      .where(eq(schema.jobFiles.id, fileId))
      .returning();

    return { success: true, file: updated[0] };
  });

  // 9. Purge All Completed/History Jobs
  fastify.delete("/history/all", async () => {
    const deleted = await db
      .delete(schema.jobs)
      .where(inArray(schema.jobs.status, ["PRINTED", "PARTIALLY_PRINTED", "FAILED", "CANCELLED"]))
      .returning({ id: schema.jobs.id });

    return { success: true, count: deleted.length };
  });

  // 10. Delete a Single Job (cascades to files, settings, attempts, and events)
  fastify.delete("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };

    const job = await db.query.jobs.findFirst({
      where: eq(schema.jobs.id, id),
    });

    if (!job) {
      return reply.status(404).send({ error: "Job not found" });
    }

    await db.delete(schema.jobs).where(eq(schema.jobs.id, id));

    return { success: true, message: `Job ${job.jobCode || id} deleted successfully` };
  });
}
