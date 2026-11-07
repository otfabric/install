#!/usr/bin/env python3
"""A stand-in for get.otfabric.io, for the installer tests.

  fake_server.py <workdir> [<windows fake exe>]

Serves the routes the installers use (/<tool>/latest, /dl/<tool>/<ver>/<file>,
/r/<tool>) from generated releases, on a free port on 127.0.0.1. Writes the
port to <workdir>/port and one JSON line per request to <workdir>/requests.jsonl.

The tool name picks the scenario:
  goodtool   a correct release (versions 1.2.3 and 1.0.0)
  badsum     the checksum does not match the archive
  nosums     no checksums file
  nomember   the archive does not contain the expected binary
  linkmember the expected member is a symlink (tar only)
  broken     the binary fails `version`
  nolatest   /latest fails
"""

import hashlib
import io
import json
import os
import socketserver
import sys
import tarfile
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

UNIX_TARGETS = ["linux-amd64", "linux-arm64", "linux-armv7", "darwin-amd64", "darwin-arm64"]
WINDOWS_TARGETS = ["windows-amd64", "windows-arm64"]
SCENARIOS = ["goodtool", "badsum", "nosums", "nomember", "linkmember", "broken"]
LATEST = "1.2.3"


def unix_binary(tool, version, ok=True):
    if not ok:
        return b"#!/bin/sh\necho 'cannot run' >&2\nexit 1\n"
    return (
        "#!/bin/sh\n"
        f'if [ "${{1:-}}" = version ]; then echo "{tool} version: {version}"; exit 0; fi\n'
        f'echo "{tool} {version} $*"\n'
    ).encode()


def tar_bytes(name, data, symlink=False):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        info = tarfile.TarInfo(name)
        if symlink:
            info.type = tarfile.SYMTYPE
            info.linkname = "/bin/sh"
            tar.addfile(info)
        else:
            info.size = len(data)
            info.mode = 0o755
            tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def zip_bytes(name, data):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(name, data)
    return buf.getvalue()


def build(windows_exe, windows_broken_exe):
    files = {}
    for tool in SCENARIOS:
        versions = [LATEST, "1.0.0"] if tool == "goodtool" else [LATEST]
        for version in versions:
            sums = []
            for target in UNIX_TARGETS + WINDOWS_TARGETS:
                windows = target.startswith("windows-")
                member = f"{tool}-{version}-{target}" + (".exe" if windows else "")
                if tool == "nomember":
                    member = "README.txt"
                if windows:
                    data = windows_broken_exe if tool == "broken" else windows_exe
                    archive = f"{tool}-{version}-{target}.zip"
                    payload = zip_bytes(member, data)
                else:
                    data = unix_binary(tool, version, ok=tool != "broken")
                    archive = f"{tool}-{version}-{target}.tar.gz"
                    payload = tar_bytes(member, data, symlink=tool == "linkmember")
                files[f"/dl/{tool}/{version}/{archive}"] = payload
                digest = hashlib.sha256(payload).hexdigest()
                if tool == "badsum":
                    digest = "0" * 64
                sums.append(f"{digest}  {archive}\n")
            if tool != "nosums":
                files[f"/dl/{tool}/{version}/{tool}-{version}-checksums.txt"] = "".join(sorted(sums)).encode()
    return files


def main():
    workdir = sys.argv[1]
    exe = b"MZ not a real program"
    broken = exe
    if len(sys.argv) > 2:
        with open(sys.argv[2], "rb") as f:
            exe = f.read()
    if len(sys.argv) > 3:
        with open(sys.argv[3], "rb") as f:
            broken = f.read()
    files = build(exe, broken)
    log = open(os.path.join(workdir, "requests.jsonl"), "a", buffering=1)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send(self, status, body=b"", ctype="text/plain"):
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            url = urlsplit(self.path)
            log.write(json.dumps({
                "path": url.path,
                "query": {k: v[0] for k, v in parse_qs(url.query, keep_blank_values=True).items()},
                "ua": self.headers.get("User-Agent", ""),
                "install": self.headers.get("X-OTF-Install", ""),
                "requested": self.headers.get("X-OTF-Requested", ""),
            }) + "\n")
            parts = url.path.strip("/").split("/")
            if len(parts) == 2 and parts[1] == "latest":
                if parts[0] == "nolatest":
                    return self.send(404, b"not found\n")
                return self.send(200, (LATEST + "\n").encode())
            if parts[0] == "r":
                return self.send(204)
            body = files.get(url.path)
            if body is None:
                return self.send(404, b"not found\n")
            return self.send(200, body, "application/octet-stream")

    class Server(ThreadingHTTPServer):
        daemon_threads = True

        def server_bind(self):
            # HTTPServer.server_bind does a reverse DNS lookup, which can hang.
            socketserver.TCPServer.server_bind(self)
            self.server_name = "127.0.0.1"
            self.server_port = self.server_address[1]

    server = Server(("127.0.0.1", 0), Handler)
    with open(os.path.join(workdir, "port.tmp"), "w") as f:
        f.write(str(server.server_address[1]))
    os.replace(os.path.join(workdir, "port.tmp"), os.path.join(workdir, "port"))
    server.serve_forever()


if __name__ == "__main__":
    main()
