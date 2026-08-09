# -*- coding: utf-8 -*-
# 反代理伺服器 — DeepSeek API 轉發（支援 SSE 串流）
# 使用方式：python proxy.py
# 然後在工具設定中填入「反代理」: http://localhost:8800
# 日誌會同時輸出到終端機與 proxy.log

from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.request, ssl, re, time, datetime, os, sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

PORT = 8800
TARGET = "https://api.deepseek.com"
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "proxy.log")
CHUNK = 8192

CORS_HEADERS = [
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
    ("Access-Control-Allow-Headers", "Authorization, Content-Type"),
]

def _now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def log_line(msg):
    line = f"[{_now()}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        # 覆寫內建 log，避免輸出醜陋預設格式
        pass

    def _fix_path(self, path):
        # 移除代理工具附加的域名前綴 e.g. /api.deepseek.com/v1/... → /v1/...
        return re.sub(r'^/api\.[^/]+', '', path)

    def _send(self, status, body, extra_headers=(), head_only=False):
        self.send_response(status)
        for k, v in CORS_HEADERS:
            self.send_header(k, v)
        for k, v in extra_headers:
            self.send_header(k, v)
        if not head_only:
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.end_headers()

    def _stream(self, resp, t0, fixed, method):
        # 逐塊轉發上游回應，支援 SSE 串流即時送達瀏覽器
        status = resp.status
        head = [(k, v) for k, v in resp.getheaders()
                if k.lower() not in ("transfer-encoding", "content-length",
                                     "access-control-allow-origin", "access-control-allow-headers",
                                     "access-control-allow-methods")]
        self.send_response(status)
        for k, v in CORS_HEADERS:
            self.send_header(k, v)
        for k, v in head:
            self.send_header(k, v)
        # 不發 Content-Length，改用 chunked 或連線結束表示結尾
        self.send_header("Content-Encoding", "identity")
        self.send_header("Connection", "close")
        self.end_headers()
        total = 0
        started = time.time()
        try:
            while True:
                chunk = resp.read(CHUNK)
                if not chunk:
                    break
                total += len(chunk)
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        ms = int((time.time() - t0) * 1000)
        log_line(f"↯ {method} {fixed} → {status} (串流 {total} bytes, {ms}ms)")

    def _run(self, method):
        t0 = time.time()
        fixed = self._fix_path(self.path)
        url = TARGET + fixed
        try:
            if method == "POST":
                body = getattr(self, "_last_body", None)
                if body is None:
                    body_len = int(self.headers.get("Content-Length", 0))
                    body = self.rfile.read(body_len)
                req = urllib.request.Request(url, data=body, method="POST")
                for k, v in self.headers.items():
                    if k.lower() not in ("host", "content-length"):
                        req.add_header(k, v)
            else:
                req = urllib.request.Request(url, method="GET")
                for k, v in self.headers.items():
                    if k.lower() != "host":
                        req.add_header(k, v)
            with urllib.request.urlopen(req, context=ssl.create_default_context()) as resp:
                # 偵測 SSE 串流（chat/completions + stream:true）→ 轉發；其餘讀完整體再回傳
                is_stream = False
                if method == "POST" and "chat/completions" in fixed:
                    try:
                        body_text = getattr(self, "_last_body", b"").decode("utf-8", errors="replace")
                        is_stream = '"stream":true' in body_text or '"stream": true' in body_text
                    except Exception:
                        is_stream = False
                if is_stream:
                    self._stream(resp, t0, fixed, method)
                else:
                    data = resp.read()
                    ms = int((time.time() - t0) * 1000)
                    status = resp.status
                    log_line(f"✓ {method} {fixed} → {status} ({len(data)} bytes, {ms}ms)")
                    extra = [(k, v) for k, v in resp.getheaders()
                             if k.lower() not in ("transfer-encoding", "access-control-allow-origin",
                                                  "access-control-allow-headers", "access-control-allow-methods")]
                    self._send(status, data, extra)
        except urllib.error.HTTPError as e:
            data = e.read()
            ms = int((time.time() - t0) * 1000)
            msg = data.decode("utf-8", errors="replace")[:300]
            log_line(f"✗ {method} {fixed} → {e.code} ({len(data)} bytes, {ms}ms)  {msg}")
            extra = [(k, v) for k, v in e.headers.items()
                     if k.lower() not in ("transfer-encoding", "access-control-allow-origin",
                                          "access-control-allow-headers", "access-control-allow-methods")]
            self._send(e.code, data, extra)
        except Exception as e:
            ms = int((time.time() - t0) * 1000)
            log_line(f"✗ {method} {fixed} → 本地錯誤 ({ms}ms)  {e}")
            self._send(502, str(e).encode())

    def do_POST(self):
        self._last_body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self._run("POST")

    def do_GET(self):
        self._run("GET")

    def do_OPTIONS(self):
        log_line(f"… OPTIONS {self._fix_path(self.path)} (CORS preflight)")
        self.send_response(200)
        for k, v in CORS_HEADERS:
            self.send_header(k, v)
        self.send_header("Content-Length", "0")
        self.end_headers()

if __name__ == "__main__":
    log_line("========== 反代理伺服器啟動（SSE 串流支援）==========")
    log_line(f"監聽 → http://localhost:{PORT}")
    log_line(f"轉發目標 → {TARGET}")
    log_line(f"日誌檔 → {LOG_FILE}")
    try:
        HTTPServer(("0.0.0.0", PORT), Proxy).serve_forever()
    except KeyboardInterrupt:
        log_line("========== 反代理伺服器已停止 ==========")
