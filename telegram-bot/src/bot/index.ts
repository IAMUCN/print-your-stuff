import { Bot, InlineKeyboard, session, SessionFlavor, Context } from "grammy";
import { config } from "../config.js";
import { db, schema } from "../db/index.js";
import { eq, and, desc, asc, inArray, sql } from "drizzle-orm";
import { PdfService } from "../services/pdf.service.js";
import { TelegramFileService } from "../services/telegram-file.service.js";

interface SessionData {
  step?: "AWAITING_NAME" | "AWAITING_CUSTOM_PAGES";
  activeDraftId?: string;
  configuringFileId?: string;
}

export type BotContext = Context & SessionFlavor<SessionData>;

// Concurrency locks & debouncers per user for multiple document uploads
const userLocks = new Map<number, Promise<void>>();
const draftSummaryTimers = new Map<number, NodeJS.Timeout>();

async function acquireUserLock<T>(userId: number, fn: () => Promise<T>): Promise<T> {
  while (userLocks.has(userId)) {
    try {
      await userLocks.get(userId);
    } catch (_) {}
  }

  let resolveLock!: () => void;
  const lockPromise = new Promise<void>((res) => {
    resolveLock = res;
  });
  userLocks.set(userId, lockPromise);

  try {
    return await fn();
  } finally {
    userLocks.delete(userId);
    resolveLock();
  }
}

export function createBot(): Bot<BotContext> {
  if (!config.telegramBotToken) {
    console.warn("⚠️ TELEGRAM_BOT_TOKEN is not configured. Bot will run in dummy mode.");
  }

  const bot = new Bot<BotContext>(config.telegramBotToken || "dummy_token");

  // In-memory session store (suitable for V1 single-instance Render deploy)
  bot.use(session({ initial: (): SessionData => ({}) }));

  // Debug logging middleware
  bot.use(async (ctx, next) => {
    console.log(
      `📩 [BOT UPDATE] User: ${ctx.from?.id} (${ctx.from?.first_name}), Text/Data: ${
        ctx.message?.text || ctx.callbackQuery?.data || ctx.message?.document?.file_name || "media"
      }`
    );
    await next();
  });

  // Global bot error handler
  bot.catch((err) => {
    console.error("❌ [BOT ERROR]", err);
  });

  // Helper: Get or create user from DB
  async function getDbUser(ctx: BotContext) {
    if (!ctx.from) return null;
    const existing = await db.query.users.findFirst({
      where: eq(schema.users.telegramUserId, ctx.from.id),
    });
    return existing || null;
  }

  // 1. /start command
  bot.command("start", async (ctx) => {
    ctx.session = {};
    const user = await getDbUser(ctx);

    if (!user) {
      ctx.session.step = "AWAITING_NAME";
      return ctx.reply(
        "👋 Welcome to the **Hostel Print Service**!\n\n" +
          "Before starting, please reply with your **Display Name**:",
        { parse_mode: "Markdown" }
      );
    }

    return sendMainMenu(ctx, user.displayName);
  });

  // 2. /clear & /reset commands
  bot.command(["clear", "reset"], async (ctx) => {
    const user = await getDbUser(ctx);
    if (user) {
      await db
        .delete(schema.jobs)
        .where(and(eq(schema.jobs.userId, user.id), eq(schema.jobs.status, "DRAFT")));
    }
    ctx.session = {};
    const timer = ctx.from ? draftSummaryTimers.get(ctx.from.id) : undefined;
    if (timer) clearTimeout(timer);
    if (ctx.from) draftSummaryTimers.delete(ctx.from.id);

    await ctx.reply(
      "🧹 **Chat session and draft cleared.**\n\n" +
        "You can start fresh anytime with /start or by sending your documents.",
      { parse_mode: "Markdown" }
    );
  });

  // 3. /jobs command
  bot.command("jobs", async (ctx) => {
    const user = await getDbUser(ctx);
    if (!user) return ctx.reply("Please type /start first to register.");
    return sendMyJobsMenu(ctx, user.id);
  });

  // 4. /name command
  bot.command("name", async (ctx) => {
    const user = await getDbUser(ctx);
    if (!user) return ctx.reply("Please type /start first to register.");

    const text = ctx.message?.text?.trim() || "";
    const parts = text.split(/\s+/);
    if (parts.length > 1) {
      const newName = parts.slice(1).join(" ").trim();
      if (newName.length < 2) {
        return ctx.reply("Please enter a name with at least 2 characters.");
      }
      await db
        .update(schema.users)
        .set({ displayName: newName })
        .where(eq(schema.users.id, user.id));
      return ctx.reply(`✅ Display name updated to: <b>${escapeHtml(newName)}</b>`, {
        parse_mode: "HTML",
      });
    }

    return ctx.reply(
      `👤 Your current display name is: <b>${escapeHtml(user.displayName)}</b>\n\n` +
        `To change your name, send:\n<code>/name Your New Name</code>`,
      { parse_mode: "HTML" }
    );
  });

  // 5. /status command
  bot.command("status", async (ctx) => {
    const user = await getDbUser(ctx);
    if (!user) return ctx.reply("Please type /start first to register.");

    const lastJob = await db.query.jobs.findFirst({
      where: and(eq(schema.jobs.userId, user.id), sql`${schema.jobs.status} != 'DRAFT'`),
      orderBy: [desc(schema.jobs.createdAt)],
      with: { files: true },
    });

    if (!lastJob) {
      return ctx.reply("No active print jobs. Send a PDF or DOCX file to start printing!");
    }

    const code = lastJob.jobCode ? `#${lastJob.jobCode}` : "Pending";
    let statusText = `📌 <b>Print Job ${code}</b>\n` +
      `Overall Status: <code>${lastJob.status}</code>\n` +
      `Date: ${lastJob.createdAt.toLocaleDateString()}\n\n` +
      `📄 <b>Files Breakdown (${lastJob.files.length}):</b>\n`;

    for (let i = 0; i < lastJob.files.length; i++) {
      const f = lastJob.files[i];
      const badge = formatFileStatusBadge(f.status || "PENDING");
      statusText += `${i + 1}. <b>${escapeHtml(f.originalFilename)}</b> — ${badge}\n`;
      if (f.errorMessage) {
        statusText += `   <i>Note: ${escapeHtml(f.errorMessage)}</i>\n`;
      }
    }

    if (lastJob.status === "WAITING") {
      statusText += `\n⏳ <i>Waiting for approval. Quote code <b>#${lastJob.jobCode}</b> at the admin desk.</i>`;
    } else if (lastJob.status === "PRINTING") {
      statusText += `\n🖨️ <i>Your job is currently being printed by the spooler!</i>`;
    } else if (lastJob.status === "PRINTED") {
      statusText += `\n✅ <i>All files in this job have been printed! You can collect your papers.</i>`;
    }

    return ctx.reply(statusText, { parse_mode: "HTML" });
  });

  // 6. /help & /commands
  bot.command(["help", "commands"], async (ctx) => {
    return sendHelpMessage(ctx);
  });

  // 7. /menu command
  bot.command("menu", async (ctx) => {
    ctx.session = {};
    const user = await getDbUser(ctx);
    if (!user) {
      ctx.session.step = "AWAITING_NAME";
      return ctx.reply(
        "👋 Welcome to the **Hostel Print Service**!\n\n" +
          "Before starting, please reply with your **Display Name**:",
        { parse_mode: "Markdown" }
      );
    }
    return sendMainMenu(ctx, user.displayName);
  });

  // Main menu renderer
  async function sendMainMenu(ctx: BotContext, name: string) {
    const keyboard = new InlineKeyboard()
      .text("📄 New Print Job", "menu_new_job")
      .row()
      .text("📋 My Jobs", "menu_my_jobs")
      .text("❓ Help & Commands", "menu_help")
      .row()
      .text("👤 Change Name", "menu_change_name")
      .text("🧹 Clear Session", "menu_clear");

    await ctx.reply(
      `🖨️ *Hostel Print Service*\nWelcome back, *${escapeMarkdown(name)}*!\n\n` +
        `Submit your PDF or Word documents below to get a print job code.\n\n` +
        `Tap *Menu* (or type /menu) anytime to view available commands.`,
      {
        parse_mode: "Markdown",
        reply_markup: keyboard,
      }
    );
  }

  // Help message renderer
  async function sendHelpMessage(ctx: BotContext) {
    const keyboard = new InlineKeyboard().text("⬅️ Back to Menu", "menu_main");
    await ctx.reply(
      `ℹ️ *Hostel Print Automation Guidelines*\n\n` +
        `• *Supported Files*: PDF, DOC, DOCX (up to 20 MB per file).\n` +
        `• *Photos & Images*: Direct image uploads (JPG/PNG) are not supported. To print photos or images, please convert them to a PDF first (e.g. using 'Print to PDF' on your phone or a scanner app) and send the PDF.\n\n` +
        `• *How it works*:\n` +
        `  1. Upload one or multiple PDFs/DOCX files.\n` +
        `  2. Configure copies, Black & White / Color, and page ranges.\n` +
        `  3. Tap Submit to get your Job Code (e.g. #1004).\n` +
        `  4. Visit the admin room with your code to get your prints approved and printed.\n\n` +
        `• *Commands*:\n` +
        `  /start - Main menu\n` +
        `  /jobs - View all your print jobs\n` +
        `  /name - View or update your display name\n` +
        `  /status - Check status of current job\n` +
        `  /clear - Clear chat session and active draft\n` +
        `  /help - Show this guide`,
      { parse_mode: "Markdown", reply_markup: keyboard }
    );
  }

  // My Jobs list renderer
  async function sendMyJobsMenu(ctx: BotContext, userId: string) {
    const userJobs = await db.query.jobs.findMany({
      where: eq(schema.jobs.userId, userId),
      orderBy: [desc(schema.jobs.createdAt)],
      limit: 10,
      with: { files: true },
    });

    const activeOrSubmitted = userJobs.filter((j) => j.status !== "DRAFT");
    if (activeOrSubmitted.length === 0) {
      const keyboard = new InlineKeyboard().text("📄 Create New Job", "menu_new_job");
      return ctx.reply("You have no print jobs yet.", { reply_markup: keyboard });
    }

    let text = `📋 <b>Your Recent Print Jobs:</b>\n\n`;
    const keyboard = new InlineKeyboard();

    for (const job of activeOrSubmitted) {
      const code = job.jobCode ? `#${job.jobCode}` : "Pending";
      const fileCount = job.files.length;
      text += `• <b>Job ${code}</b> — <code>${job.status}</code> (${fileCount} file${fileCount > 1 ? "s" : ""})\n`;
      for (let i = 0; i < job.files.length; i++) {
        const f = job.files[i];
        text += `   ${i + 1}. ${escapeHtml(f.originalFilename)} — ${formatFileStatusBadge(f.status || "PENDING")}\n`;
      }
      text += `   <i>${job.createdAt.toLocaleDateString()}</i>\n\n`;

      if (job.status === "WAITING") {
        keyboard.text(`❌ Cancel #${job.jobCode}`, `cancel_job_${job.id}`).row();
      }
    }

    keyboard.text("🏠 Main Menu", "menu_main");
    await ctx.reply(text, { parse_mode: "HTML", reply_markup: keyboard });
  }

  // Handle name registration and custom page text input
  bot.on("message:text", async (ctx, next) => {
    if (ctx.session.step === "AWAITING_NAME") {
      const name = ctx.message.text.trim();
      if (name.length < 2) {
        return ctx.reply("Please enter a valid name (at least 2 characters):");
      }

      await db.insert(schema.users).values({
        telegramUserId: ctx.from.id,
        displayName: name,
        role: "STUDENT",
      });

      ctx.session.step = undefined;
      return sendMainMenu(ctx, name);
    }

    if (ctx.session.step === "AWAITING_CUSTOM_PAGES" && ctx.session.configuringFileId) {
      const pageRange = ctx.message.text.trim();
      const isValid = /^(all|\d+(-\d+)?(,\s*\d+(-\d+)?)*)$/i.test(pageRange);
      if (!isValid) {
        return ctx.reply("❌ Invalid page format. Please use standard formats like <code>1-5</code>, <code>1,3,7-10</code>, or reply <code>all</code>.", {
          parse_mode: "HTML",
        });
      }

      const fileId = ctx.session.configuringFileId;
      const normalizedRange = pageRange.toLowerCase() === "all" ? null : pageRange;

      await db
        .update(schema.printSettings)
        .set({ pageRange: normalizedRange })
        .where(eq(schema.printSettings.jobFileId, fileId));

      ctx.session.step = undefined;
      ctx.session.configuringFileId = undefined;
      await ctx.reply(`✅ Page range set to: <b>${escapeHtml(normalizedRange || "All Pages")}</b>`, {
        parse_mode: "HTML",
      });

      if (ctx.session.activeDraftId) {
        return renderDraftSummary(ctx, ctx.session.activeDraftId);
      }
      return;
    }

    return next();
  });

  // Menu Callbacks
  bot.callbackQuery("menu_main", async (ctx) => {
    await ctx.answerCallbackQuery();
    const user = await getDbUser(ctx);
    if (user) await sendMainMenu(ctx, user.displayName);
  });

  bot.callbackQuery("menu_help", async (ctx) => {
    await ctx.answerCallbackQuery();
    return sendHelpMessage(ctx);
  });

  bot.callbackQuery("menu_my_jobs", async (ctx) => {
    await ctx.answerCallbackQuery();
    const user = await getDbUser(ctx);
    if (!user) return;
    return sendMyJobsMenu(ctx, user.id);
  });

  bot.callbackQuery("menu_change_name", async (ctx) => {
    await ctx.answerCallbackQuery();
    ctx.session.step = "AWAITING_NAME";
    await ctx.reply(
      "👤 <b>Change Display Name</b>\n\n" +
        "Please reply with your new display name (or use <code>/name Your Name</code>):",
      { parse_mode: "HTML" }
    );
  });

  bot.callbackQuery("menu_clear", async (ctx) => {
    await ctx.answerCallbackQuery();
    const user = await getDbUser(ctx);
    if (user) {
      await db
        .delete(schema.jobs)
        .where(and(eq(schema.jobs.userId, user.id), eq(schema.jobs.status, "DRAFT")));
    }
    ctx.session = {};
    const timer = ctx.from ? draftSummaryTimers.get(ctx.from.id) : undefined;
    if (timer) clearTimeout(timer);
    if (ctx.from) draftSummaryTimers.delete(ctx.from.id);

    await ctx.reply(
      "🧹 <b>Session and active drafts cleared.</b>\n\n" +
        "You can start fresh anytime by sending a document or tapping /start.",
      { parse_mode: "HTML" }
    );
    if (user) {
      await sendMainMenu(ctx, user.displayName);
    }
  });

  // Cancel an active waiting job
  bot.callbackQuery(/^cancel_job_(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const jobId = ctx.match[1];
    await db
      .update(schema.jobs)
      .set({ status: "CANCELLED", updatedAt: new Date() })
      .where(eq(schema.jobs.id, jobId));

    await ctx.reply("✅ The print job has been cancelled.");
    const user = await getDbUser(ctx);
    if (user) await sendMainMenu(ctx, user.displayName);
  });

  // Start new print job
  bot.callbackQuery("menu_new_job", async (ctx) => {
    await ctx.answerCallbackQuery();
    const user = await getDbUser(ctx);
    if (!user) return;

    // Check for existing draft
    let draft = await db.query.jobs.findFirst({
      where: and(eq(schema.jobs.userId, user.id), eq(schema.jobs.status, "DRAFT")),
      with: { files: { with: { settings: true } } },
    });

    if (!draft) {
      const [newJob] = await db
        .insert(schema.jobs)
        .values({
          userId: user.id,
          status: "DRAFT",
        })
        .returning();
      draft = { ...newJob, files: [] };
    }

    ctx.session.activeDraftId = draft.id;

    if (draft.files.length > 0) {
      return renderDraftSummary(ctx, draft.id);
    }

    await ctx.reply(
      `📄 *New Print Job Started*\n\n` +
        `Please send your documents now.\n` +
        `• Supported: PDFs, Word Docs (.docx / .doc)\n` +
        `• You can select and send multiple files at once!\n\n` +
        `ℹ️ _To print photos or images, please convert them to PDF first._`,
      { parse_mode: "Markdown" }
    );
  });

  // Reject direct photo uploads with guidance
  bot.on("message:photo", async (ctx) => {
    return ctx.reply(
      "⚠️ <b>Photos are not directly supported.</b>\n\n" +
        "To print photos or images, please convert them to a PDF first (e.g. using 'Print to PDF' or an image scanner app) and send the PDF document here.",
      { parse_mode: "HTML" }
    );
  });

  // Handle Document Uploads (PDF / DOCX / DOC)
  bot.on("message:document", async (ctx) => {
    const user = await getDbUser(ctx);
    if (!user) return ctx.reply("Please type /start first to register.");

    const doc = ctx.message.document;
    if (doc.file_size && doc.file_size > 20 * 1024 * 1024) {
      return ctx.reply("❌ File is too large. Maximum allowed size is 20 MB.");
    }

    const filename = doc.file_name || "document.pdf";
    const ext = filename.toLowerCase().split(".").pop() || "";

    // Friendly rejection for images uploaded as documents
    const imageExts = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg", "heic"];
    if (imageExts.includes(ext)) {
      return ctx.reply(
        `⚠️ <b>Image files (.${escapeHtml(ext)}) are not directly supported.</b>\n\n` +
          "To print photos or images, please convert them to a PDF first (e.g. using 'Print to PDF' or an image scanner app) and upload the PDF document.",
        { parse_mode: "HTML" }
      );
    }

    const allowedExts = ["pdf", "docx", "doc"];
    if (!allowedExts.includes(ext)) {
      return ctx.reply(
        "❌ <b>Unsupported file format.</b>\n\n" +
          "Supported formats are: <b>PDF, DOC, DOCX</b>.\n" +
          "To print images, please convert them to a PDF first.",
        { parse_mode: "HTML" }
      );
    }

    // Process file under user concurrency lock so multiple PDFs sent at once join the same draft
    return acquireUserLock(ctx.from.id, async () => {
      let draftId = ctx.session.activeDraftId;
      if (!draftId) {
        const existingDraft = await db.query.jobs.findFirst({
          where: and(eq(schema.jobs.userId, user.id), eq(schema.jobs.status, "DRAFT")),
          orderBy: [desc(schema.jobs.createdAt)],
        });
        if (existingDraft) {
          draftId = existingDraft.id;
        } else {
          const [newJob] = await db
            .insert(schema.jobs)
            .values({ userId: user.id, status: "DRAFT" })
            .returning();
          draftId = newJob.id;
        }
        ctx.session.activeDraftId = draftId;
      }

      let mime = doc.mime_type || "application/octet-stream";
      let inputType: "PDF" | "DOC" | "DOCX" = "PDF";
      if (ext === "docx") {
        inputType = "DOCX";
        mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
      } else if (ext === "doc") {
        inputType = "DOC";
        mime = "application/msword";
      }

      let pageCount: number | null = null;
      if (inputType === "PDF") {
        try {
          const buffer = await TelegramFileService.downloadFileBuffer(doc.file_id);
          pageCount = await PdfService.getPdfPageCount(buffer);
        } catch (e) {
          console.warn("Could not read PDF page count on upload:", e);
        }
      }

      const [jobFile] = await db
        .insert(schema.jobFiles)
        .values({
          jobId: draftId,
          telegramFileId: doc.file_id,
          originalFilename: filename,
          mimeType: mime,
          sizeBytes: doc.file_size || 0,
          inputType,
          pageCount,
        })
        .returning();

      // Default settings: Black & White
      await db.insert(schema.printSettings).values({
        jobFileId: jobFile.id,
        copies: 1,
        colorMode: "BW",
        pagesPerSheet: 1,
        orientation: "AUTO",
        imageLayout: "FIT",
      });

      await ctx.reply(`📎 Added: <b>${escapeHtml(filename)}</b> ${pageCount ? `(${pageCount} pages)` : ""}`, {
        parse_mode: "HTML",
      });

      // Debounce draft summary display so sending multiple PDFs at once produces ONE aggregated summary
      const currentDraftId = draftId;
      const existingTimer = draftSummaryTimers.get(ctx.from.id);
      if (existingTimer) clearTimeout(existingTimer);

      draftSummaryTimers.set(
        ctx.from.id,
        setTimeout(() => {
          draftSummaryTimers.delete(ctx.from.id);
          renderDraftSummary(ctx, currentDraftId);
        }, 600)
      );
    });
  });

  function buildConfigFileKeyboard(file: any): InlineKeyboard {
    const s = file.settings;
    const keyboard = new InlineKeyboard();

    // Copies control with live count
    keyboard
      .text("➖ 1 Copy", `copies_dec_${file.id}`)
      .text(`📄 ${s.copies} Cop${s.copies > 1 ? "ies" : "y"}`, `noop`)
      .text("➕ 1 Copy", `copies_inc_${file.id}`)
      .row();

    // Color mode toggle (B&W first)
    const isColor = s.colorMode === "COLOR";
    keyboard
      .text(!isColor ? "🔘 B&W (Black)" : "⚪ B&W", `color_toggle_${file.id}_BW`)
      .text(isColor ? "🔘 Color (CMYK)" : "⚪ Color", `color_toggle_${file.id}_COLOR`)
      .row();

    // Custom page range
    keyboard
      .text(`📑 Pages: ${s.pageRange || "All Pages"}`, `set_pages_${file.id}`)
      .row();

    keyboard.text("💾 Save & Return to Draft", `view_draft_${file.jobId}`);
    return keyboard;
  }

  function formatConfigFileMessage(file: any): string {
    const s = file.settings;
    const colorLabel = s.colorMode === "COLOR" ? "🌈 Color (CMYK)" : "⚫ Black & White (Grayscale)";
    const pageLabel = s.pageRange ? s.pageRange : "All Pages";

    return (
      `⚙️ <b>Configure Document Settings</b>\n\n` +
      `📁 <b>File:</b> <code>${escapeHtml(file.originalFilename)}</code>\n` +
      `📄 <b>Copies:</b> <b>${s.copies}</b>\n` +
      `🎨 <b>Color Mode:</b> <b>${colorLabel}</b>\n` +
      `📑 <b>Pages:</b> <b>${escapeHtml(pageLabel)}</b>\n\n` +
      `<i>Tap the buttons below to change settings in real-time.</i>`
    );
  }

  // Draft summary & settings menu renderer
  async function renderDraftSummary(ctx: BotContext, jobId: string) {
    const job = await db.query.jobs.findFirst({
      where: eq(schema.jobs.id, jobId),
      with: { files: { with: { settings: true } } },
    });

    if (!job || job.files.length === 0) {
      return ctx.reply("Your draft has no files. Send a PDF or DOCX file to begin.");
    }

    let text = `📄 <b>PRINT JOB DRAFT (${job.files.length} file${job.files.length > 1 ? "s" : ""})</b>\n\n`;

    for (let i = 0; i < job.files.length; i++) {
      const file = job.files[i];
      const s = file.settings;
      const pages = file.pageCount ? `${file.pageCount} pgs` : "Pages pending";
      const color = s?.colorMode === "COLOR" ? "🌈 Color" : "⚫ B&W";
      const copies = `${s?.copies || 1} cop${(s?.copies || 1) > 1 ? "ies" : "y"}`;
      const pageRange = s?.pageRange ? ` · Pgs: ${s.pageRange}` : "";

      text += `<b>${i + 1}. ${escapeHtml(file.originalFilename)}</b>\n`;
      text += `   ↳ ${pages} · ${copies} · ${color}${pageRange}\n\n`;
    }

    const keyboard = new InlineKeyboard()
      .text("⚙️ Configure Settings", `config_job_${jobId}`)
      .row()
      .text("➕ Add More Files", `add_files_${jobId}`)
      .text("❌ Discard", `discard_draft_${jobId}`)
      .row()
      .text("🚀 SUBMIT JOB", `submit_job_${jobId}`);

    await ctx.reply(text, { parse_mode: "HTML", reply_markup: keyboard });
  }

  // Configure settings entry
  bot.callbackQuery(/^config_job_(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const jobId = ctx.match[1];
    const job = await db.query.jobs.findFirst({
      where: eq(schema.jobs.id, jobId),
      with: { files: true },
    });

    if (!job) return;

    const keyboard = new InlineKeyboard();
    for (const f of job.files) {
      keyboard.text(`⚙️ ${f.originalFilename.slice(0, 20)}`, `config_file_${f.id}`).row();
    }
    keyboard.text("⬅️ Back to Summary", `view_draft_${jobId}`);

    await ctx.reply("Select which file you want to configure:", { reply_markup: keyboard });
  });

  // Configure specific file
  bot.callbackQuery(/^config_file_(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const fileId = ctx.match[1];
    const file = await db.query.jobFiles.findFirst({
      where: eq(schema.jobFiles.id, fileId),
      with: { settings: true },
    });

    if (!file || !file.settings) return;

    await ctx.reply(formatConfigFileMessage(file), {
      parse_mode: "HTML",
      reply_markup: buildConfigFileKeyboard(file),
    });
  });

  // Setting actions: Copies
  bot.callbackQuery(/^copies_(inc|dec)_(.+)$/, async (ctx) => {
    const action = ctx.match[1];
    const fileId = ctx.match[2];

    const current = await db.query.printSettings.findFirst({
      where: eq(schema.printSettings.jobFileId, fileId),
    });
    if (!current) {
      await ctx.answerCallbackQuery();
      return;
    }

    let newCopies = action === "inc" ? current.copies + 1 : current.copies - 1;
    if (newCopies < 1) newCopies = 1;
    if (newCopies > 50) newCopies = 50;

    await db
      .update(schema.printSettings)
      .set({ copies: newCopies })
      .where(eq(schema.printSettings.jobFileId, fileId));

    await ctx.answerCallbackQuery({ text: `Copies set to ${newCopies}` });

    // Re-render file config
    const file = await db.query.jobFiles.findFirst({
      where: eq(schema.jobFiles.id, fileId),
      with: { settings: true },
    });
    if (file) {
      try {
        await ctx.editMessageText(formatConfigFileMessage(file), {
          parse_mode: "HTML",
          reply_markup: buildConfigFileKeyboard(file),
        });
      } catch (_) {}
    }
  });

  // Setting actions: Color
  bot.callbackQuery(/^color_toggle_(.+)_(COLOR|BW)$/, async (ctx) => {
    const fileId = ctx.match[1];
    const newColor = ctx.match[2] as "COLOR" | "BW";

    await db
      .update(schema.printSettings)
      .set({ colorMode: newColor })
      .where(eq(schema.printSettings.jobFileId, fileId));

    await ctx.answerCallbackQuery({
      text: `Color set to: ${newColor === "COLOR" ? "Color (CMYK)" : "Black & White"}`,
    });

    const file = await db.query.jobFiles.findFirst({
      where: eq(schema.jobFiles.id, fileId),
      with: { settings: true },
    });
    if (file) {
      try {
        await ctx.editMessageText(formatConfigFileMessage(file), {
          parse_mode: "HTML",
          reply_markup: buildConfigFileKeyboard(file),
        });
      } catch (_) {}
    }
  });

  // No-op handler for informational button labels
  bot.callbackQuery("noop", async (ctx) => {
    await ctx.answerCallbackQuery();
  });

  bot.callbackQuery(/^set_pages_(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const fileId = ctx.match[1];
    ctx.session.step = "AWAITING_CUSTOM_PAGES";
    ctx.session.configuringFileId = fileId;
    await ctx.reply(
      "Please reply with your desired page range (e.g. <code>1-5</code> or <code>1,3,7-10</code>, or reply <code>all</code>):",
      { parse_mode: "HTML" }
    );
  });

  bot.callbackQuery(/^view_draft_(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const jobId = ctx.match[1];
    return renderDraftSummary(ctx, jobId);
  });

  bot.callbackQuery(/^add_files_(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    await ctx.reply("Send more PDFs or DOCX files to attach them to this print job!");
  });

  bot.callbackQuery(/^discard_draft_(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const jobId = ctx.match[1];
    await db.delete(schema.jobs).where(eq(schema.jobs.id, jobId));
    ctx.session.activeDraftId = undefined;
    await ctx.reply("Draft discarded.");
    const user = await getDbUser(ctx);
    if (user) await sendMainMenu(ctx, user.displayName);
  });

  // SUBMIT JOB
  bot.callbackQuery(/^submit_job_(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const jobId = ctx.match[1];

    const job = await db.query.jobs.findFirst({
      where: eq(schema.jobs.id, jobId),
      with: { files: true },
    });

    if (!job || job.files.length === 0) {
      return ctx.reply("No files in job to submit.");
    }

    if (job.status !== "DRAFT") {
      return ctx.reply(`⚠️ This job has already been submitted with code #${job.jobCode || ""}.`);
    }

    // Allocate sequential Job Code starting at 1001
    const seqResult = await db.execute(sql`SELECT nextval('job_code_seq') as next_val;`);
    const nextCode = Number(seqResult[0]?.next_val || 1001);

    const now = new Date();
    const expiresAt = new Date(now.getTime() + 48 * 3600 * 1000); // 48h expiration

    await db
      .update(schema.jobs)
      .set({
        jobCode: nextCode,
        status: "WAITING",
        submittedAt: now,
        expiresAt: expiresAt,
        updatedAt: now,
      })
      .where(eq(schema.jobs.id, jobId));

    await db.insert(schema.jobEvents).values({
      jobId,
      eventType: "JOB_SUBMITTED",
      metadata: { jobCode: nextCode, fileCount: job.files.length },
    });

    ctx.session.activeDraftId = undefined;

    const keyboard = new InlineKeyboard()
      .text("📋 View in My Jobs", "menu_my_jobs")
      .row()
      .text("🏠 Main Menu", "menu_main");

    await ctx.reply(
      `✅ *Print Job Submitted Successfully!*\n\n` +
        `🎫 *Your Job Code:* \`#${nextCode}\`\n` +
        `📌 *Status:* \`WAITING FOR APPROVAL\`\n\n` +
        `🚶‍♂️ *Next Step:*\n` +
        `Please visit the hostel admin's room and quote code *#${nextCode}* to get your documents printed.\n\n` +
        `⏳ _Unprinted jobs expire after 48 hours._`,
      { parse_mode: "Markdown", reply_markup: keyboard }
    );
  });

  function escapeMarkdown(text: string): string {
    return text.replace(/[_*[\]()~`>#+-=|{}.!]/g, "\\$&");
  }

  function escapeHtml(text: string): string {
    if (!text) return "";
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function formatFileStatusBadge(status: string): string {
    switch (status) {
      case "PRINTED":
        return "✅ Printed";
      case "PRINTING":
        return "🖨️ Printing...";
      case "FAILED":
        return "❌ Failed";
      case "PENDING":
      default:
        return "⏳ Queued";
    }
  }

  return bot;
}

export async function registerBotCommands(bot: Bot<any>) {
  try {
    await bot.api.setMyCommands([
      { command: "start", description: "Start the bot & submit documents" },
      { command: "menu", description: "Open main navigation menu" },
      { command: "jobs", description: "View your submitted print jobs & codes" },
      { command: "status", description: "Check status of your active print job" },
      { command: "name", description: "View or change your display name" },
      { command: "clear", description: "Clear current draft & reset chat session" },
      { command: "help", description: "Help guide, formats & instructions" },
    ]);
    console.log("✅ Registered native command menu with Telegram API");
  } catch (err: any) {
    console.warn("⚠️ Could not register bot commands with Telegram:", err.message);
  }
}
