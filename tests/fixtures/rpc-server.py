"""Stand-in JSON-RPC server for wait-for-server.sh tests.

argv[1]  file the chosen port is written to
argv[2]  file every POST is appended to, one line per call
argv[3]  optional count of leading POSTs answered with a non-JSON-RPC body,
         simulating a server that is listening before its RPC layer serves
"""

import http.server
import json
import sys

WARMUP_CALLS = int(sys.argv[3]) if len(sys.argv) > 3 else 0
calls = 0


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        global calls
        calls += 1
        with open(sys.argv[2], "a", encoding="utf-8") as record:
            record.write("reset\n")

        if calls <= WARMUP_CALLS:
            # Listening, but not yet answering JSON-RPC: the case that used to
            # fail the run outright instead of being retried.
            body = b"<html>starting up</html>"
            self.send_response(503)
            self.send_header("Content-Type", "text/html")
        else:
            # A JSON-RPC error carried by HTTP 4xx still means the RPC layer is
            # up, so readiness must accept it.
            body = json.dumps(
                {"jsonrpc": "2.0", "error": {"code": -32601}, "id": 1}
            ).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")

        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w", encoding="utf-8") as port_file:
    port_file.write(str(server.server_port))
server.serve_forever()
