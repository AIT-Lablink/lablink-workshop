from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import threading
import time

from opcua import ua, Server
from opcua.server.binary_server_asyncio import BinaryServer

ROOT = os.path.dirname(os.path.abspath(__file__))
TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
}
NAMES = ("QLoa", "mSub", "TSupSub", "TRetSub")
nodes = {}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/values":
            self.send_values()
            return
        rel = "index.html" if path == "/" else path.lstrip("/")
        self.send_file(rel)

    def do_PUT(self):
        path = self.path.split("?", 1)[0]
        if path != "/qloa":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 1000:
            self.send_error(400, "Expected a JSON body")
            return
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            value = float(body["value"])
        except (ValueError, KeyError, TypeError, json.JSONDecodeError, UnicodeError):
            self.send_error(400, "Expected {\"value\": watts}")
            return
        if value < 20000 or value > 100000:
            self.send_error(400, "QLoa must be between 20000 and 100000 W")
            return
        nodes["QLoa"].set_value(ua.Variant(value, ua.VariantType.Double))
        self.send_json(200, {"value": value})

    def send_values(self):
        payload = {"connected": True}
        for name in NAMES:
            try:
                value = nodes[name].get_value()
                payload[name] = float(value)
            except (TypeError, ValueError):
                payload[name] = None
                payload["connected"] = False
        self.send_json(200, payload)

    def send_json(self, status, payload):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_file(self, rel):
        file_path = os.path.normpath(os.path.join(ROOT, rel))
        if file_path != ROOT and not file_path.startswith(ROOT + os.sep):
            self.send_error(403)
            return
        if not os.path.isfile(file_path):
            self.send_error(404)
            return
        with open(file_path, "rb") as handle:
            data = handle.read()
        ext = os.path.splitext(file_path)[1]
        self.send_response(200)
        self.send_header("Content-Type", TYPES.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def serve_http():
    port = int(os.environ.get("HTTP_PORT", "80"))
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


def main():
    server = Server()
    server.set_server_name("SimpleDH OPC UA Server")
    # Address clients connect to. It is not an address of this container
    # (station IP, or host.docker.internal on Docker Desktop), so the socket
    # listens on every interface and the published port forwards connections in.
    server.set_endpoint(os.environ.get(
        "OPCUA_ENDPOINT", "opc.tcp://host.docker.internal:12345/simpledh"))
    server.set_security_policy([ua.SecurityPolicyType.NoSecurity])
    server.bserver = BinaryServer(server.iserver, "0.0.0.0", server.endpoint.port)

    idx = server.register_namespace("urn:lablink:simpledh")
    loads = server.nodes.objects.add_folder(idx, "SimpleDH")
    nodes["QLoa"] = loads.add_variable(
        "ns={};s=SimpleDH/QLoa;".format(idx), "QLoa", 80000.0, ua.VariantType.Double)
    nodes["QLoa"].set_writable()

    # Written by the Lablink client from FMU outputs. Not subscribed.
    for name, value in (("mSub", 0.0), ("TSupSub", 300.0), ("TRetSub", 300.0)):
        written = loads.add_variable(
            "ns={};s=SimpleDH/{};".format(idx, name), name, value, ua.VariantType.Double)
        written.set_writable()
        nodes[name] = written

    server.start()
    threading.Thread(target=serve_http, daemon=True).start()
    try:
        while True:
            time.sleep(1)
    finally:
        server.stop()


if __name__ == "__main__":
    main()
