"""仅供本机开发验证的 HTTP 适配器，与游戏 Host 使用同一 CLI 内核。"""
import argparse
import json
import mimetypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit
import core


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, code, content, kind="application/json; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        try:
            relative = unquote(urlsplit(self.path).path).lstrip("/")
            if not relative:
                path = core.ROOT / "tools/asset-workbench/harness.html"
            elif relative.startswith("__jobs/"):
                path = core.safe_path(core.JOBS, relative[len("__jobs/"):])
            else:
                path = core.safe_path(core.ROOT / "launcher/web", relative)
            data = path.read_bytes()
            kind = mimetypes.guess_type(path)[0] or "application/octet-stream"
            if path.suffix == ".json":
                base = f"http://127.0.0.1:{self.server.server_port}"
                data = data.replace(b"https://asset-workbench.local", (base + "/__jobs").encode()).replace(b"https://overlay.local", base.encode())
            self.respond(200, data, kind)
        except (OSError, core.WorkbenchError):
            self.respond(404, b"{}")

    def do_POST(self):
        origin = f"http://127.0.0.1:{self.server.server_port}"
        if self.path != "/api" or self.headers.get("Origin") != origin or self.headers.get("Host") != origin.removeprefix("http://"):
            self.respond(403, b"{}"); return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 16384:
                raise ValueError("请求大小不合法")
            result = core.api(json.loads(self.rfile.read(size)))
            text = json.dumps({"success": True, "data": result}, ensure_ascii=False)
            text = text.replace("https://asset-workbench.local", origin + "/__jobs")
            self.respond(200, text.encode("utf-8"))
        except Exception as error:
            self.respond(200, json.dumps({"success": False, "error": str(error)}, ensure_ascii=False).encode("utf-8"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18764)
    args = parser.parse_args()
    print(f"素材工作台开发预览：http://127.0.0.1:{args.port}/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
