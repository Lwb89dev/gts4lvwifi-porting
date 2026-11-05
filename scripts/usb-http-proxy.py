#!/usr/bin/env python3
"""HTTP forward proxy for the tablet, on the USB cable only.

The tablet has no route past the cable and this PC does no NAT (that would
need root). A package manager on the tablet reaches the Arch Linux ARM mirrors
through this proxy instead:

    scripts/usb-http-proxy.py &
    ssh root@172.16.42.1 'http_proxy=http://172.16.42.2:3128 pacman -Sy'

It binds to the host's USB address (172.16.42.2) and nothing else, handles GET
and HEAD for http:// URLs and CONNECT for https, and passes redirects on to the
client unchanged. It logs one line per request. Stop it with Ctrl-C or kill.
"""
import argparse
import http.client
import http.server
import select
import socket
import subprocess
import urllib.parse

HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "proxy-connection", "te", "trailers", "transfer-encoding", "upgrade",
}
CHUNK = 64 * 1024


def forward_headers(headers):
    return {k: v for k, v in headers.items() if k.lower() not in HOP_BY_HOP}


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)

    def do_GET(self):
        self.relay()

    def do_HEAD(self):
        self.relay()

    def relay(self):
        url = urllib.parse.urlsplit(self.path)
        if url.scheme != "http" or not url.hostname:
            self.send_error(400, "only absolute http:// URLs, or CONNECT")
            return
        target = url.path or "/"
        if url.query:
            target += "?" + url.query
        try:
            conn = http.client.HTTPConnection(url.hostname, url.port or 80, timeout=60)
            conn.request(self.command, target, headers=forward_headers(self.headers))
            resp = conn.getresponse()
        except OSError as err:
            self.send_error(502, str(err))
            return
        self.send_response(resp.status, resp.reason)
        for key, value in resp.getheaders():
            if key.lower() not in HOP_BY_HOP:
                self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.copy_body(resp)
        conn.close()

    def copy_body(self, resp):
        while True:
            block = resp.read(CHUNK)
            if not block:
                return
            self.wfile.write(block)

    def do_CONNECT(self):
        host, _, port = self.path.partition(":")
        try:
            upstream = socket.create_connection((host, int(port or 443)), timeout=30)
        except (OSError, ValueError) as err:
            self.send_error(502, str(err))
            return
        self.send_response(200, "Connection established")
        self.end_headers()
        self.tunnel(self.connection, upstream)
        upstream.close()

    @staticmethod
    def tunnel(client, upstream):
        pair = [client, upstream]
        while True:
            ready, _, _ = select.select(pair, [], [], 60)
            if not ready:
                return
            for sock in ready:
                data = sock.recv(CHUNK)
                if not data:
                    return
                (upstream if sock is client else client).sendall(data)


def route_source(target):
    """The address the host uses to reach <target>: the tablet's DHCP gave it."""
    out = subprocess.run(["ip", "-4", "route", "get", target], capture_output=True,
                         text=True, check=False).stdout.split()
    if "src" not in out:
        raise SystemExit(f"usb-http-proxy: no route to {target}")
    return out[out.index("src") + 1]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--bind", default=None,
                        help="host USB address (default: the source address of the route to 172.16.42.1)")
    parser.add_argument("--port", type=int, default=3128)
    args = parser.parse_args()
    args.bind = args.bind or route_source("172.16.42.1")
    server = http.server.ThreadingHTTPServer((args.bind, args.port), Proxy)
    print(f"proxy on {args.bind}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
