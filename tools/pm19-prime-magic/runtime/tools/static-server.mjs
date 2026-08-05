import { createReadStream, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";

const root = normalize(new URL("..", import.meta.url).pathname);
const mime = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".map", "application/json"],
]);

const server = createServer((request, response) => {
  const requestPath = request.url === "/" ? "/web/index.html" : (request.url ?? "/web/index.html");
  const relative = normalize(requestPath.split("?", 1)[0]).replace(/^[/\\]+/, "");
  const path = join(root, relative);
  if (!path.startsWith(root)) {
    response.writeHead(403).end("forbidden");
    return;
  }
  try {
    const stat = statSync(path);
    if (!stat.isFile()) throw new Error("not a file");
    response.writeHead(200, {
      "content-type": mime.get(extname(path)) ?? "application/octet-stream",
      "cache-control": "no-store",
      // Enables SharedArrayBuffer worker experiments on localhost.
      "cross-origin-opener-policy": "same-origin",
      "cross-origin-embedder-policy": "require-corp",
    });
    createReadStream(path).pipe(response);
  } catch {
    response.writeHead(404).end("not found");
  }
});

server.listen(4173, "127.0.0.1", () => {
  process.stdout.write("Prime Magic Orbit demo: http://127.0.0.1:4173/\n");
});
