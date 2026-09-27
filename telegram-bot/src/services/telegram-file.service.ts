import { config } from "../config.js";
import https from "node:https";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const CACHE_DIR = path.resolve(process.cwd(), "cache");
if (!fs.existsSync(CACHE_DIR)) {
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
  } catch (_) {}
}

function httpsGet(url: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    https.get(url, { family: 4 }, (res) => {
      if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        httpsGet(res.headers.location).then(resolve, reject);
        return;
      }
      if (res.statusCode && res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode}: ${res.statusMessage}`));
        return;
      }
      const chunks: Buffer[] = [];
      res.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
      res.on("end", () => resolve(Buffer.concat(chunks)));
      res.on("error", reject);
    }).on("error", reject);
  });
}

export class TelegramFileService {
  /**
   * Fetches the direct download URL for a Telegram file_id using Telegram Bot API
   */
  static async getFileUrl(fileId: string): Promise<string> {
    const url = `https://api.telegram.org/bot${config.telegramBotToken}/getFile?file_id=${fileId}`;
    const buf = await httpsGet(url);
    const data = JSON.parse(buf.toString()) as { ok: boolean; result?: { file_path?: string } };

    if (!data.ok || !data.result?.file_path) {
      throw new Error(`Failed to resolve Telegram file path for file_id: ${fileId}`);
    }

    return `https://api.telegram.org/file/bot${config.telegramBotToken}/${data.result.file_path}`;
  }

  /**
   * Downloads a Telegram file into a memory buffer (Uint8Array) with local disk caching
   */
  static async downloadFileBuffer(fileId: string): Promise<Uint8Array> {
    const safeName = crypto.createHash("sha256").update(fileId).digest("hex") + ".bin";
    const cacheFile = path.join(CACHE_DIR, safeName);

    if (fs.existsSync(cacheFile)) {
      return new Uint8Array(fs.readFileSync(cacheFile));
    }

    const fileUrl = await this.getFileUrl(fileId);
    const buffer = await httpsGet(fileUrl);

    try {
      fs.writeFileSync(cacheFile, buffer);
    } catch (_) {}

    return new Uint8Array(buffer);
  }
}
