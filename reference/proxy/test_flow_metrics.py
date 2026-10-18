import argparse
import asyncio
import json
import tempfile
import unittest
from pathlib import Path

from proxy import Proxy


class FlowMetricsTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "mode.txt").write_text("block")
        args = argparse.Namespace(allow_client=["127.0.0.1"], log=self.root / "events.jsonl",
                                  mode_file=self.root / "mode.txt")
        self.proxy = Proxy(args)
        self.proxy_server = await asyncio.start_server(self.proxy.handle, "127.0.0.1", 0)
        self.port = self.proxy_server.sockets[0].getsockname()[1]

    async def asyncTearDown(self):
        self.proxy_server.close()
        await self.proxy_server.wait_closed()
        for task in tuple(self.proxy.handlers):
            task.cancel()
        await asyncio.gather(*self.proxy.handlers, return_exceptions=True)
        self.proxy.log.close()
        self.temp.cleanup()

    async def test_blocked_connect_never_contacts_upstream(self):
        calls = []
        async def forbidden_upstream(host, port):
            calls.append((host, port))
            raise AssertionError("Blocked request reached upstream")
        self.proxy.upstream = forbidden_upstream
        reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
        writer.write(b"CONNECT ad.doubleclick.net:443 HTTP/1.1\r\nHost: ad.doubleclick.net:443\r\n\r\n")
        await writer.drain()
        response = await reader.read()
        writer.close()
        await writer.wait_closed()
        self.assertTrue(response.startswith(b"HTTP/1.1 403"))
        self.assertEqual(calls, [])
        records = [json.loads(line) for line in (self.root / "events.jsonl").read_text().splitlines()]
        self.assertEqual([row["event"] for row in records], ["blocked"])

    async def test_metrics_preserve_transferred_bytes_and_server_endpoint(self):
        request = bytes(range(256)) * 1000
        response = bytes(reversed(range(256))) * 1500
        received = []
        async def origin(reader, writer):
            received.append(await reader.readexactly(len(request)))
            writer.write(response)
            await writer.drain()
            writer.close()
            await writer.wait_closed()
        upstream = await asyncio.start_server(origin, "127.0.0.1", 0)
        upstream_port = upstream.sockets[0].getsockname()[1]
        async def test_upstream(host, port):
            self.assertEqual((host, port), ("test.googlevideo.com", 443))
            return await asyncio.open_connection("127.0.0.1", upstream_port)
        self.proxy.upstream = test_upstream
        try:
            reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
            writer.write(b"CONNECT test.googlevideo.com:443 HTTP/1.1\r\nHost: test.googlevideo.com:443\r\n\r\n")
            await writer.drain()
            self.assertTrue((await reader.readuntil(b"\r\n\r\n")).startswith(b"HTTP/1.1 200"))
            writer.write(request)
            await writer.drain()
            self.assertEqual(await reader.read(), response)
            writer.close()
            await writer.wait_closed()
            self.assertEqual(received, [request])
            records = [json.loads(line) for line in (self.root / "events.jsonl").read_text().splitlines()]
            opened, closed = records
            self.assertEqual((opened["event"], closed["event"]), ("tunnel", "flow_closed"))
            self.assertEqual(opened["flow_id"], closed["flow_id"])
            self.assertEqual(closed["bytes_from_client"], len(request))
            self.assertEqual(closed["bytes_from_server"], len(response))
            self.assertEqual((closed["server_ip"], closed["server_port"]), ("127.0.0.1", upstream_port))
            self.assertLessEqual(closed["first_server_byte"], closed["last_server_byte"])
            self.assertEqual(self.proxy.flows, {})
        finally:
            upstream.close()
            await upstream.wait_closed()


if __name__ == "__main__":
    unittest.main()
