import * as dotenv from "dotenv";

dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || "3000", 10),
  host: process.env.HOST || "0.0.0.0",
  databaseUrl: process.env.DATABASE_URL || "postgresql://postgres:password@localhost:5432/hostel_print",
  telegramBotToken: process.env.TELEGRAM_BOT_TOKEN || "",
  webhookUrl: process.env.WEBHOOK_URL || "",
  jwtSecret: process.env.JWT_SECRET || "default_development_jwt_secret_key_12345",
  initialAdmin: {
    username: process.env.ADMIN_USERNAME || "admin",
    password: process.env.ADMIN_PASSWORD || "adminpassword123",
  },
};
