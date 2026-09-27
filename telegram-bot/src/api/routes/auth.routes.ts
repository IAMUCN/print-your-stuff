import { FastifyInstance } from "fastify";
import { db, schema } from "../../db/index.js";
import { eq } from "drizzle-orm";
import bcrypt from "bcryptjs";

export async function authRoutes(fastify: FastifyInstance) {
  // Login
  fastify.post("/login", async (request, reply) => {
    const { username, password } = request.body as { username?: string; password?: string };

    if (!username || !password) {
      return reply.status(400).send({ error: "Username and password are required" });
    }

    const admin = await db.query.users.findFirst({
      where: eq(schema.users.username, username),
    });

    if (!admin || !admin.passwordHash || admin.role !== "ADMIN") {
      return reply.status(401).send({ error: "Invalid admin credentials" });
    }

    const isMatch = await bcrypt.compare(password, admin.passwordHash);
    if (!isMatch) {
      return reply.status(401).send({ error: "Invalid admin credentials" });
    }

    const token = fastify.jwt.sign(
      { id: admin.id, username: admin.username, role: admin.role },
      { expiresIn: "7d" }
    );

    return {
      token,
      admin: {
        id: admin.id,
        username: admin.username,
        displayName: admin.displayName,
      },
    };
  });

  // Verify session
  fastify.get("/me", async (request, reply) => {
    try {
      await request.jwtVerify();
      const user = request.user as { id: string; username: string; role: string };
      return { authenticated: true, user };
    } catch (err) {
      return reply.status(401).send({ error: "Unauthorized session" });
    }
  });
}
