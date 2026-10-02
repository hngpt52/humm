#!/usr/bin/env python3
# A stand-in for OpenAI's transcription endpoint, for testing how Humm copes with failures:
#   python3 scripts/stub-openai.py hang-first 8765
#   build/Humm.app/Contents/MacOS/Humm --selftest <audio> 1 --endpoint http://127.0.0.1:8765/v1/audio/transcriptions
# The self-test sends it a dummy key, never the real one. Modes:
#   hang-first  the first request is read and never answered (a dead connection); the rest succeed
#   hang-all    nothing is ever answered
#   500-first   the first request gets HTTP 500; the rest succeed
#   401         every request is refused (a bad key)
#   ok          every request succeeds
import json, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
mode, port = sys.argv[1], int(sys.argv[2])
count = 0
lock = threading.Lock()
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *args): pass
    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        global count
        with lock:
            count += 1
            n = count
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        print(f"{time.strftime('%H:%M:%S')} request {n} from port {self.client_address[1]}", flush=True)
        if mode == "hang-all" or (mode == "hang-first" and n == 1):
            time.sleep(300)
            return
        if mode == "500-first" and n == 1:
            return self.reply(500, {"error": {"message": "The server had an error"}})
        if mode == "401":
            return self.reply(401, {"error": {"message": "Incorrect API key provided: sk-stub****0000"}})
        self.reply(200, {"text": "Stub transcript.", "usage": {"type": "tokens", "input_tokens": 10, "output_tokens": 3, "total_tokens": 13}})
ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
