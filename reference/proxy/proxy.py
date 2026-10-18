#!/usr/bin/env python3
"""Proxy de diagnostic iPhone, avec inspection HTTPS locale ciblée en option."""

import argparse
import asyncio
import contextlib
import ipaddress
import json
import re
import socket
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit
from inspection.video_filter_config import read_config as read_video_filter


AD_DOMAINS = ("doubleclick.net", "googleadservices.com", "googlesyndication.com")
INSPECT_HOSTS = ("youtubei.googleapis.com", "youtubei-att.googleapis.com")
RELATED_DOMAINS = AD_DOMAINS + (
    "youtube.com", "youtu.be", "googlevideo.com", "ytimg.com",
    "youtubei.googleapis.com", "youtubei-att.googleapis.com", "youtube.googleapis.com", "yt3.ggpht.com",
)
HOSTNAME = re.compile(r"[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?\Z")


def matches(host, domains):
    return any(host == domain or host.endswith("." + domain) for domain in domains)


def inspect_host(host, include_media=False):
    return host in INSPECT_HOSTS or (include_media and matches(host, ("googlevideo.com",)))


class Proxy:
    def __init__(self, args):
        self.args = args
        self.allowed = {ipaddress.ip_address(value) for value in args.allow_client}
        self.allowed.add(ipaddress.ip_address("127.0.0.1"))
        self.connections = set()
        self.flows = {}
        self.handlers = set()
        self.started = datetime.now(timezone.utc).isoformat()
        self.log = args.log.open("a", encoding="utf-8")

    def event(self, event, **fields):
        entry = {"time": datetime.now(timezone.utc).isoformat(), "event": event, **fields}
        line = json.dumps(entry, ensure_ascii=False)
        self.log.write(line + "\n")
        self.log.flush()
        print(line, flush=True)

    def mode(self):
        value = self.args.mode_file.read_text(encoding="utf-8").strip()
        if value not in ("observe", "block"):
            raise ValueError("Le fichier de mode doit contenir observe ou block")
        return value

    def https_mode(self):
        path = getattr(self.args, "https_mode_file", None)
        if path and path.exists():
            value = path.read_text().strip()
            if value in ("off", "observe", "observe-media"):
                return value
        return "off"

    async def inspection_upstream(self, host, client, flow_id):
        reader, writer = await asyncio.wait_for(asyncio.open_connection("127.0.0.1", self.args.https_port), 5)
        try:
            writer.write((f"CONNECT {host}:443 HTTP/1.1\r\nHost: {host}:443\r\n"
                          f"X-Poc-Client-IP: {client}\r\nX-Poc-Flow-ID: {flow_id}\r\n\r\n").encode("ascii"))
            await writer.drain()
            response = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 15)
            if response.split(b"\r\n", 1)[0].split(b" ")[1] != b"200":
                raise OSError("Inspection locale indisponible")
            return reader, writer
        except BaseException:
            writer.close()
            await writer.wait_closed()
            raise

    async def response(self, writer, status, text):
        body = text.encode("utf-8")
        writer.write((
            f"HTTP/1.1 {status}\r\nContent-Type: text/plain; charset=utf-8\r\n"
            f"Content-Length: {len(body)}\r\nConnection: close\r\n"
            "Cache-Control: no-store\r\n\r\n"
        ).encode("ascii") + body)
        await writer.drain()

    async def upstream(self, host, port):
        # Résoudre une seule fois puis utiliser l'IP validée : aucune passerelle
        # vers le LAN, localhost, les adresses de métadonnées ou des ports privés.
        addresses = await asyncio.get_running_loop().getaddrinfo(
            host, port, type=socket.SOCK_STREAM,
        )
        if not addresses or any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):
            raise ValueError("Destination non publique interdite")
        last_error = OSError("Aucune destination disponible")
        for family, _, _, _, address in addresses:
            try:
                return await asyncio.wait_for(
                    asyncio.open_connection(address[0], port, family=family), 8,
                )
            except (OSError, asyncio.TimeoutError) as exc:
                last_error = exc
        raise last_error

    def flow_event(self, event, flow, **fields):
        self.event(event, **{k: v for k, v in flow.items() if not k.startswith("_")},
                   duration_seconds=round(time.monotonic() - flow["_started"], 3), **fields)
        flow["_reported"] = (flow["bytes_from_server"], flow["bytes_from_client"])

    async def relay(self, reader, writer, flow=None, direction=None):
        while data := await reader.read(65536):
            if flow is not None:
                flow[direction] += len(data)
                if direction == "bytes_from_server":
                    now = datetime.now(timezone.utc).isoformat()
                    flow["first_server_byte"] = flow["first_server_byte"] or now
                    flow["last_server_byte"] = now
            writer.write(data)
            await writer.drain()

    async def handle(self, reader, writer):
        self.handlers.add(asyncio.current_task())
        upstream_writer = None
        tasks = []
        tunneled = False
        host = None
        flow = None
        client = None
        close_reason = "closed"
        self.connections.add(writer)
        try:
            client = ipaddress.ip_address(writer.get_extra_info("peername")[0])
            if client not in self.allowed:
                await self.response(writer, "403 Forbidden", "Client non autorisé.\n")
                return
            async with asyncio.timeout(15):
                headers = await reader.readuntil(b"\r\n\r\n")
            first_line = headers.split(b"\r\n", 1)[0].decode("ascii")
            method, target, version = first_line.split(" ")
            if version not in ("HTTP/1.0", "HTTP/1.1"):
                raise ValueError("Version HTTP invalide")
            mode = self.mode()
            if method == "GET" and urlsplit(target).hostname == "poc.test":
                if urlsplit(target).path == "/youtube-poc.cer":
                    cert_file = getattr(self.args, "cert_file", None)
                    if cert_file and cert_file.exists():
                        body = cert_file.read_bytes()
                        writer.write(("HTTP/1.1 200 OK\r\nContent-Type: application/x-x509-ca-cert\r\n"
                                      "Content-Disposition: attachment; filename=YouTube-PoC-Local.cer\r\n"
                                      f"Content-Length: {len(body)}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").encode() + body)
                        await writer.drain()
                        self.event("certificate_downloaded", client_ip=str(client))
                        return
                self.event("diagnostic", mode=mode)
                await self.response(writer, "200 OK", (
                    f"Connexion au proxy : OK\nMode : {mode}\n\n"
                    "Ce contrôle vérifie Safari uniquement.\n"
                    "Ouvre ensuite l'application YouTube pour observer ses connexions.\n"
                    f"Inspection HTTPS : {self.https_mode()}\n"
                    "Certificat local du test : http://poc.test/youtube-poc.cer\n"
                    "Les flux googlevideo restent chiffrés de bout en bout.\n"
                ))
                return
            if method != "CONNECT":
                await self.response(writer, "501 Not Implemented", (
                    "Ce test transporte HTTPS uniquement. Diagnostic : http://poc.test\n"
                ))
                return
            host, port_text = target.rsplit(":", 1)
            host = host.lower().rstrip(".")
            if not HOSTNAME.fullmatch(host) or port_text != "443":
                raise ValueError("Seules les destinations HTTPS sur le port 443 sont autorisées")
            if mode == "block" and matches(host, AD_DOMAINS):
                self.event("blocked", host=host, mode=mode, client_ip=str(client))
                await self.response(writer, "403 Forbidden", "Domaine bloqué par le test.\n")
                return
            flow_id = uuid.uuid4().hex
            https_mode = self.https_mode()
            inspection = https_mode != "off" and inspect_host(host, https_mode == "observe-media")
            async with asyncio.timeout(25):
                if inspection:
                    upstream_reader, upstream_writer = await self.inspection_upstream(host, client, flow_id)
                else:
                    upstream_reader, upstream_writer = await self.upstream(host, 443)
            writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            await writer.drain()
            tunneled = True
            if matches(host, RELATED_DOMAINS):
                peer = upstream_writer.get_extra_info("peername")
                flow = {"flow_id": flow_id, "host": host, "mode": mode, "client_ip": str(client),
                        "server_ip": peer[0], "server_port": peer[1],
                        "started_at": datetime.now(timezone.utc).isoformat(),
                        "bytes_from_server": 0, "bytes_from_client": 0,
                        "first_server_byte": None, "last_server_byte": None,
                        "_started": time.monotonic(), "_reported": (0, 0)}
                if inspection:
                    flow["transport"] = "local_https_inspector"
                    flow["endpoint_note"] = "Relais local ; IP Google dans le journal API"
                self.flows[flow_id] = flow
                self.flow_event("tunnel", flow)
            tasks = [
                asyncio.create_task(self.relay(reader, upstream_writer, flow, "bytes_from_client")),
                asyncio.create_task(self.relay(upstream_reader, writer, flow, "bytes_from_server")),
            ]
            async with asyncio.timeout(900):
                await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            if any(task.done() and not task.cancelled() and task.exception() for task in tasks):
                close_reason = "transfer_error"
        except (OSError, ValueError, asyncio.TimeoutError, asyncio.IncompleteReadError,
                asyncio.LimitOverrunError) as exc:
            close_reason = type(exc).__name__
            if host and matches(host, RELATED_DOMAINS) and not tunneled:
                self.event("connection_error", host=host, error=type(exc).__name__, client_ip=str(client))
            if not tunneled:
                with contextlib.suppress(OSError):
                    await self.response(writer, "502 Bad Gateway", "Connexion impossible.\n")
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            if flow is not None:
                self.flow_event("flow_closed", flow, close_reason=close_reason)
                self.flows.pop(flow["flow_id"], None)
            for connection in (writer, upstream_writer):
                if connection:
                    connection.close()
                    with contextlib.suppress(OSError):
                        await connection.wait_closed()
            self.connections.discard(writer)
            self.handlers.discard(asyncio.current_task())

    async def watch_mode(self):
        previous = (self.mode(), self.https_mode(), read_video_filter())
        last_report = time.monotonic()
        while True:
            await asyncio.sleep(0.5)
            if time.monotonic() - last_report >= 2:
                for flow in tuple(self.flows.values()):
                    if flow["_reported"] != (flow["bytes_from_server"], flow["bytes_from_client"]):
                        self.flow_event("flow_progress", flow)
                last_report = time.monotonic()
            try:
                current = (self.mode(), self.https_mode(), read_video_filter())
            except (OSError, ValueError):
                continue
            if current != previous:
                # Fermer les tunnels pour que le changement affecte aussi les
                # connexions qui existaient avant le passage à la nouvelle phase.
                for writer in tuple(self.connections):
                    writer.close()
                self.event("mode_changed", mode=current[0], https_mode=current[1], video_filter=current[2])
                previous = current

    async def run(self):
        self.mode()  # Vérifier la configuration avant d'ouvrir le port.
        server = await asyncio.start_server(
            self.handle, self.args.listen, self.args.port, limit=16384,
        )
        self.event("started", listen=self.args.listen, port=self.args.port, mode=self.mode(), https_mode=self.https_mode())
        monitor = asyncio.create_task(self.watch_mode())
        try:
            async with server:
                await server.serve_forever()
        finally:
            monitor.cancel()
            await asyncio.gather(monitor, return_exceptions=True)
            for writer in tuple(self.connections):
                writer.close()
            for task in tuple(self.handlers):
                task.cancel()
            await asyncio.gather(*self.handlers, return_exceptions=True)
            self.log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8877)
    parser.add_argument("--allow-client", action="append", default=[])
    parser.add_argument("--mode-file", type=Path, default=Path(__file__).with_name("mode.txt"))
    parser.add_argument("--log", type=Path, default=Path(__file__).with_name("events.jsonl"))
    parser.add_argument("--https-mode-file", type=Path, default=Path(__file__).parent / "inspection/https-mode.txt")
    parser.add_argument("--https-port", type=int, default=8880)
    parser.add_argument("--cert-file", type=Path, default=Path(__file__).parent / "inspection/https-ca/mitmproxy-ca-cert.cer")
    args = parser.parse_args()
    if args.listen != "127.0.0.1" and not args.allow_client:
        parser.error("Indiquer --allow-client avec l'adresse IP de l'iPhone")
    try:
        asyncio.run(Proxy(args).run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
