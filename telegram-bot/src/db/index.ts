import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema.js";
import { config } from "../config.js";

const client = postgres(config.databaseUrl, {
  prepare: false, // Recommended for serverless / pooled connections
  idle_timeout: 20,
  max_lifetime: 60 * 30,
  connect_timeout: 30,
});

export const db = drizzle(client, { schema });
export { schema };
