import { db, schema } from "./index.js";
import { config } from "../config.js";
import bcrypt from "bcryptjs";
import { eq } from "drizzle-orm";
import { sql } from "drizzle-orm";

export async function seed() {
  console.log("🌱 Running database seed and sequence initialization...");

  try {
    // 1. Ensure sequential job_code sequence exists starting at 1001
    await db.execute(sql`
      CREATE SEQUENCE IF NOT EXISTS job_code_seq START WITH 1001 INCREMENT BY 1;
    `);
    console.log("✅ Sequence job_code_seq ensured (starts at 1001)");

    // 2. Check and seed admin user
    const existingAdmin = await db.query.users.findFirst({
      where: eq(schema.users.role, "ADMIN"),
    });

    if (!existingAdmin) {
      const passwordHash = await bcrypt.hash(config.initialAdmin.password, 12);
      await db.insert(schema.users).values({
        username: config.initialAdmin.username,
        passwordHash: passwordHash,
        displayName: "Hostel Admin",
        role: "ADMIN",
      });
      console.log(`✅ Default admin created: ${config.initialAdmin.username}`);
    } else {
      console.log(`ℹ️ Admin user already exists: ${existingAdmin.username || existingAdmin.displayName}`);
    }

    console.log("🌱 Seeding finished successfully.");
  } catch (error) {
    console.error("❌ Seeding failed:", error);
    throw error;
  }
}



