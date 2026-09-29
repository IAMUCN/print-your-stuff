import {
  pgTable,
  uuid,
  text,
  bigint,
  integer,
  timestamp,
  pgEnum,
  jsonb,
} from "drizzle-orm/pg-core";
import { relations } from "drizzle-orm";

export const userRoleEnum = pgEnum("user_role", ["STUDENT", "ADMIN"]);
export const jobStatusEnum = pgEnum("job_status", [
  "DRAFT",
  "WAITING",
  "PRINTING",
  "PRINTED",
  "PARTIALLY_PRINTED",
  "FAILED",
  "CANCELLED",
]);
export const inputTypeEnum = pgEnum("input_type", ["PDF", "IMAGE", "DOC", "DOCX"]);
export const colorModeEnum = pgEnum("color_mode", ["COLOR", "BW"]);
export const orientationEnum = pgEnum("orientation", ["PORTRAIT", "LANDSCAPE", "AUTO"]);
export const imageLayoutEnum = pgEnum("image_layout", [
  "ONE_PER_PAGE",
  "TWO_PER_PAGE",
  "FIT",
  "ORIGINAL",
]);
export const attemptStatusEnum = pgEnum("attempt_status", [
  "STARTED",
  "PRINTED",
  "PARTIALLY_PRINTED",
  "FAILED",
  "CANCELLED",
]);

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  telegramUserId: bigint("telegram_user_id", { mode: "number" }).unique(),
  username: text("username").unique(),
  passwordHash: text("password_hash"),
  displayName: text("display_name").notNull(),
  role: userRoleEnum("role").notNull().default("STUDENT"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const jobs = pgTable("jobs", {
  id: uuid("id").primaryKey().defaultRandom(),
  jobCode: bigint("job_code", { mode: "number" }).unique(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  status: jobStatusEnum("status").notNull().default("DRAFT"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  submittedAt: timestamp("submitted_at", { withTimezone: true }),
  expiresAt: timestamp("expires_at", { withTimezone: true }),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const jobFiles = pgTable("job_files", {
  id: uuid("id").primaryKey().defaultRandom(),
  jobId: uuid("job_id")
    .notNull()
    .references(() => jobs.id, { onDelete: "cascade" }),
  telegramFileId: text("telegram_file_id").notNull(),
  originalFilename: text("original_filename").notNull(),
  mimeType: text("mime_type").notNull(),
  sizeBytes: bigint("size_bytes", { mode: "number" }).notNull(),
  inputType: inputTypeEnum("input_type").notNull(),
  pageCount: integer("page_count"),
  sortOrder: integer("sort_order").notNull().default(0),
  status: text("status").notNull().default("PENDING"),
  errorMessage: text("error_message"),
  printedAt: timestamp("printed_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const printSettings = pgTable("print_settings", {
  id: uuid("id").primaryKey().defaultRandom(),
  jobFileId: uuid("job_file_id")
    .notNull()
    .unique()
    .references(() => jobFiles.id, { onDelete: "cascade" }),
  pageRange: text("page_range"),
  copies: integer("copies").notNull().default(1),
  colorMode: colorModeEnum("color_mode").notNull().default("BW"),
  pagesPerSheet: integer("pages_per_sheet").notNull().default(1),
  orientation: orientationEnum("orientation").notNull().default("AUTO"),
  imageLayout: imageLayoutEnum("image_layout").notNull().default("FIT"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const printAttempts = pgTable("print_attempts", {
  id: uuid("id").primaryKey().defaultRandom(),
  jobId: uuid("job_id")
    .notNull()
    .references(() => jobs.id, { onDelete: "cascade" }),
  initiatedBy: uuid("initiated_by")
    .notNull()
    .references(() => users.id),
  status: attemptStatusEnum("status").notNull(),
  startedAt: timestamp("started_at", { withTimezone: true }).notNull().defaultNow(),
  completedAt: timestamp("completed_at", { withTimezone: true }),
  errorMessage: text("error_message"),
  printerName: text("printer_name"),
});

export const jobEvents = pgTable("job_events", {
  id: uuid("id").primaryKey().defaultRandom(),
  jobId: uuid("job_id")
    .notNull()
    .references(() => jobs.id, { onDelete: "cascade" }),
  eventType: text("event_type").notNull(),
  metadata: jsonb("metadata"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// Relations
export const usersRelations = relations(users, ({ many }) => ({
  jobs: many(jobs),
}));

export const jobsRelations = relations(jobs, ({ one, many }) => ({
  user: one(users, {
    fields: [jobs.userId],
    references: [users.id],
  }),
  files: many(jobFiles),
  attempts: many(printAttempts),
  events: many(jobEvents),
}));

export const jobFilesRelations = relations(jobFiles, ({ one }) => ({
  job: one(jobs, {
    fields: [jobFiles.jobId],
    references: [jobs.id],
  }),
  settings: one(printSettings, {
    fields: [jobFiles.id],
    references: [printSettings.jobFileId],
  }),
}));

export const printSettingsRelations = relations(printSettings, ({ one }) => ({
  file: one(jobFiles, {
    fields: [printSettings.jobFileId],
    references: [jobFiles.id],
  }),
}));

export const printAttemptsRelations = relations(printAttempts, ({ one }) => ({
  job: one(jobs, {
    fields: [printAttempts.jobId],
    references: [jobs.id],
  }),
  user: one(users, {
    fields: [printAttempts.initiatedBy],
    references: [users.id],
  }),
}));

export const jobEventsRelations = relations(jobEvents, ({ one }) => ({
  job: one(jobs, {
    fields: [jobEvents.jobId],
    references: [jobs.id],
  }),
}));
