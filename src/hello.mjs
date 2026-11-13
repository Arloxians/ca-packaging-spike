import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { DatabaseSync } from "node:sqlite";
const server = new McpServer({ name: "hello", version: "0.1.0" });
server.tool("ping", "Returns pong plus the Node version and a node:sqlite result", {}, async () => {
  const db = new DatabaseSync(":memory:");
  const row = db.prepare("select sqlite_version() as v").get();
  return { content: [{ type: "text", text: `pong node=${process.version} sqlite=${row.v}` }] };
});
server.connect(new StdioServerTransport());
