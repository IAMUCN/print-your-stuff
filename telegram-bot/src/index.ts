import dns from "node:dns";
dns.setDefaultResultOrder("ipv4first");

process.on("unhandledRejection", (reason) => {
  console.error("⚠️ [PROCESS UNHANDLED REJECTION]", reason);
});

process.on("uncaughtException", (err) => {
  console.error("⚠️ [PROCESS UNCAUGHT EXCEPTION]", err);
});

import Fastify from "fastify";
import cors from "@fastify/cors";
import jwt from "@fastify/jwt";
import { webhookCallback } from "grammy";
import { config } from "./config.js";
import { createBot } from "./bot/index.js";
import { authRoutes } from "./api/routes/auth.routes.js";
import { jobsRoutes } from "./api/routes/jobs.routes.js";
import { seed } from "./db/seed.js";
import { db, schema } from "./db/index.js";
import { and, eq, lt, sql } from "drizzle-orm";

async function startServer() {
  const fastify = Fastify({
    logger: true,
  });

  // Enable CORS
  await fastify.register(cors, {
    origin: true,
  });

  // Enable JWT
  await fastify.register(jwt, {
    secret: config.jwtSecret,
  });

  // Healthcheck endpoint
  fastify.get("/health", async () => {
    return { status: "ok", timestamp: new Date().toISOString() };
  });

  // Initialize bot
  const bot = createBot();

  // Mount Telegram Webhook route
  if (config.webhookUrl) {
    fastify.post(
      "/api/v1/telegram/webhook",
      webhookCallback(bot, "fastify", {
        timeoutMilliseconds: 30000,
      })
    );
  }

  // Mount REST API groups
  await fastify.register(authRoutes, { prefix: "/api/v1/auth" });
  await fastify.register(jobsRoutes, { prefix: "/api/v1/jobs", bot });

  // Automatic retention & expiration worker (runs every 15 minutes)
  setInterval(async () => {
    try {
      const now = new Date();
      // Expire unprinted waiting jobs based on expiresAt
      const expiredJobs = await db
        .update(schema.jobs)
        .set({ status: "CANCELLED", updatedAt: now })
        .where(
          and(
            eq(schema.jobs.status, "WAITING"),
            lt(schema.jobs.expiresAt, now)
          )
        )
        .returning();

      if (expiredJobs.length > 0) {
        fastify.log.info(`Cleaned up ${expiredJobs.length} expired unprinted jobs.`);
      }

      // Clean up abandoned draft jobs older than 72 hours
      const draftThreshold = new Date(Date.now() - 72 * 3600 * 1000);
      await db
        .delete(schema.jobs)
        .where(
          and(
            eq(schema.jobs.status, "DRAFT"),
            lt(schema.jobs.createdAt, draftThreshold)
          )
        );
    } catch (e) {
      fastify.log.error(e, "Error running retention cleaner");
    }
  }, 15 * 60 * 1000);

  // Initialize database seed & start server
  try {
    if (config.databaseUrl) {
      await seed().catch((err) => {
        fastify.log.warn(`Database seed skipped or failed (check connection string): ${err.message}`);
      });
    }

    await fastify.listen({ port: config.port, host: config.host });
    console.log(`🚀 Fastify Server listening on http://${config.host}:${config.port}`);

    // Set Webhook in production or run Long-Polling in local dev
    if (config.webhookUrl) {
      const targetWebhook = `${config.webhookUrl}/api/v1/telegram/webhook`;
      await bot.api.setWebhook(targetWebhook);
      console.log(`📡 Telegram Webhook set to: ${targetWebhook}`);
    } else if (config.telegramBotToken) {
      console.log("🔄 Starting Telegram bot in local Long-Polling mode...");
      bot.start({
        onStart: (info) => console.log(`🤖 Bot @${info.username} is running and listening!`),
      });
    } else {
      console.log("ℹ️ No TELEGRAM_BOT_TOKEN provided; bot polling skipped.");
    }
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
}

startServer();
