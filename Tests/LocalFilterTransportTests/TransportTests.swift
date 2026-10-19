import XCTest
import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
@testable import LocalFilterTransport
@testable import LocalFilterCore

final class TransportTests: XCTestCase {
    func testScopeAndResolvedAddressRestrictions() throws {
        XCTAssertEqual(DestinationPolicy.authority("YOUTUBEI.GOOGLEAPIS.COM:443"), "youtubei.googleapis.com")
        for value in ["example.org:443", "googlevideo.com.evil.test:443", "youtubei.googleapis.com:80",
                      "user@youtubei.googleapis.com:443", "a..googlevideo.com:443", "127.0.0.1:443"] {
            XCTAssertNil(DestinationPolicy.authority(value), value)
        }
        for value in ["127.0.0.1", "10.2.3.4", "192.168.1.1", "100.64.0.1", "169.254.1.1",
                      "172.31.0.1", "198.19.0.1", "203.0.113.1", "::1", "::ffff:127.0.0.1", "fe80::1", "fc00::1", "2001:db8::1"] {
            XCTAssertFalse(DestinationPolicy.isPublic(try SocketAddress(ipAddress: value, port: 443)), value)
        }
        for value in ["8.8.8.8", "2001:4860:4860::8888"] {
            XCTAssertTrue(DestinationPolicy.isPublic(try SocketAddress(ipAddress: value, port: 443)))
        }
    }

    func testCertificateAndKeyMustMatch() throws {
        let a = try CertificateAuthority.generate(), b = try CertificateAuthority.generate()
        XCTAssertThrowsError(try CertificateAuthority(certificatePEM: a.certificatePEM, privateKeyPEM: b.privateKeyPEM))
    }

    func testPublicCertificateDownloadIsExplicitAndLimited() throws {
        let disabled = try Lab { _ in Reply(Data()) }
        defer { disabled.stop() }
        XCTAssertEqual(try disabled.fetch("http://127.0.0.1:\(disabled.port)/certificate.cer", useProxy: false).status, 403)
        let enabled = try Lab(servesCertificate: true) { _ in Reply(Data()) }
        defer { enabled.stop() }
        let response = try enabled.fetch("http://127.0.0.1:\(enabled.port)/certificate.cer", useProxy: false)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, enabled.publicDER)
        XCTAssertTrue(response.headers.contains("application/x-x509-ca-cert"))
        XCTAssertEqual(try enabled.fetch("http://127.0.0.1:\(enabled.port)/ca-key.pem", useProxy: false).status, 403)
    }

    func testDownstreamCancellationDoesNotReportUpstreamFailure() throws {
        let cancelled = expectation(description: "client cancellation classified")
        let lab = try Lab(log: { event in
            if event.hasPrefix("request_cancelled ") { cancelled.fulfill() }
            XCTAssertFalse(event.hasPrefix("upstream_failed "), event)
        }) { _ in Reply(Data(repeating: 1, count: 1024), fragment: 1, delayMilliseconds: 2000) }
        defer { lab.stop() }
        let response = try lab.fetch("https://youtubei.googleapis.com/unrelated", allowCurlFailure: true, maxTime: 0.5)
        XCTAssertEqual(response.exitCode, 28) // curl timeout abandons an otherwise healthy upstream response.
        wait(for: [cancelled], timeout: 2)
    }

    func testTLSPlayerRewriteGzipAndUnrelatedResponse() throws {
        let clean = Wire.field(2, Data()) + Wire.field(11, Wire.field(1, Data("demoVideo01".utf8)))
        let original = clean + Wire.field(7, Data([1])) + Wire.field(68, Data([2]))
        let gzip = try OnesieCrypto.gzip(original, compress: true)
        let lab = try Lab { request in
            if request.uri == "/youtubei/v1/player" { return Reply(gzip, encoding: "gzip") }
            return Reply(original)
        }
        defer { lab.stop() }
        let rewritten = try lab.fetch("https://youtubei.googleapis.com/youtubei/v1/player")
        XCTAssertEqual(rewritten.status, 200)
        XCTAssertEqual(rewritten.body, clean)
        XCTAssertFalse(rewritten.headers.lowercased().contains("content-encoding: gzip"))
        XCTAssertFalse(rewritten.headers.lowercased().contains("etag:"))
        let unrelated = try lab.fetch("https://youtubei.googleapis.com/unrelated")
        XCTAssertEqual(unrelated.body, original)
    }

    func testStreamingFragmentDoesNotEndResponseAndMediaIsPreserved() throws {
        let clean = Wire.field(2, Data()) + Wire.field(11, Wire.field(1, Data("demoVideo01".utf8)))
        let player = clean + Wire.field(7, Data([1]))
        let header = UMP.part(10, Wire.integer(1, 0) + Wire.field(4, Data()))
        let originalBody = UMP.part(11, Wire.integer(1, 1) + Wire.integer(2, 200) + Wire.field(4, player))
        let expectedBody = UMP.part(11, Wire.integer(1, 1) + Wire.integer(2, 200) + Wire.field(4, clean))
        let media = UMP.part(12, Data(repeating: 0xa5, count: 32 * 1024))
        let original = header + originalBody + media
        let lab = try Lab { _ in Reply(original, mime: "application/vnd.yt-ump", fragment: 3) }
        defer { lab.stop() }
        let response = try lab.fetch("https://rr1.googlevideo.com/initplayback")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, header + expectedBody + media)
        XCTAssertTrue(response.headers.lowercased().contains("transfer-encoding: chunked"))
    }

    func testEncryptedProgramLearnsKeyFromHTTPSConfiguration() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("LocalFilterCoreTests/Fixtures/onesie.json")
        struct Fixture: Decodable { let kind: Int; let compressed: Bool; let key, input, expectedPlain, media: Data }
        let fixture = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: fixtureURL)).first { $0.kind == 25 && $0.compressed }!
        let wrapped = Data(repeating: 0x22, count: 32)
        let keyConfig = Wire.field(1, fixture.key) + Wire.field(2, wrapped) + Wire.integer(3, 600)
        let config = Wire.field(1, Wire.field(16, Wire.field(7, Wire.field(138536474, Wire.field(146311580, keyConfig)))))
        let lab = try Lab { request in
            if request.uri == "/youtubei/v1/log_event" {
                // The proxy must remove the stale hash before it can learn a key.
                return Reply(request.headers.contains(name: "x-youtube-hot-hash-data") ? Data() : config)
            }
            return Reply(fixture.input, mime: "application/vnd.yt-ump", fragment: 7)
        }
        defer { lab.stop() }
        let hot = try lab.fetch("https://youtubei.googleapis.com/youtubei/v1/log_event", headers: ["x-youtube-hot-hash-data: stale"])
        XCTAssertEqual(hot.body, config)
        let response = try lab.fetch("https://rr1.googlevideo.com/initplayback", body: Wire.field(3, Wire.field(5, wrapped)))
        var bytes = [UInt8](response.body)
        let first = try XCTUnwrap(UMP.read(bytes)), firstLength = try XCTUnwrap(UMP.read(bytes, at: first.1))
        bytes = Array(bytes.dropFirst(firstLength.1 + Int(firstLength.0)))
        let second = try XCTUnwrap(UMP.read(bytes)), secondLength = try XCTUnwrap(UMP.read(bytes, at: second.1))
        let payload = Data(bytes[secondLength.1..<(secondLength.1 + Int(secondLength.0))])
        let cipher = try XCTUnwrap(Wire.child(payload, 1)), tag = try XCTUnwrap(Wire.child(payload, 2))
        let iv = try XCTUnwrap(Wire.child(payload, 3))
        XCTAssertTrue(OnesieCrypto.authenticated(cipher, iv: iv, tag: tag, key: fixture.key))
        let plain = try OnesieCrypto.decode(OnesieCrypto.crypt(cipher, key: fixture.key, iv: iv), compression: 1)
        XCTAssertEqual(plain, fixture.expectedPlain)
        XCTAssertEqual(response.body.suffix(fixture.media.count), fixture.media)
    }

    func testOversizedAndMalformedAPIPassThrough() throws {
        let oversized = Data(repeating: 0xa5, count: HTTPUtilities.bodyLimit + 1024)
        let lab = try Lab { request in Reply(request.uri.contains("large") ? oversized : Data([0xff]), omitLength: true) }
        defer { lab.stop() }
        XCTAssertEqual(try lab.fetch("https://youtubei.googleapis.com/youtubei/v1/player?large=1").body, oversized)
        XCTAssertEqual(try lab.fetch("https://youtubei.googleapis.com/youtubei/v1/player").body, Data([0xff]))
    }

    func testUntrustedUpstreamFailsAndOutOfScopeConnectIsRejected() throws {
        let upstreamTLS = expectation(description: "upstream TLS rejection is identifiable")
        let scopedRejection = expectation(description: "out-of-scope CONNECT is identifiable")
        let lab = try Lab(trustUpstream: false, log: { event in
            if event.hasPrefix("upstream_failed ") && event.hasSuffix("reason=tls_handshake") { upstreamTLS.fulfill() }
            if event == "connect_rejected reason=destination_or_request" { scopedRejection.fulfill() }
        }) { _ in Reply(Data("must not pass".utf8)) }
        defer { lab.stop() }
        XCTAssertEqual(try lab.fetch("https://youtubei.googleapis.com/youtubei/v1/player").status, 502)
        let denied = try lab.fetch("https://example.org/", allowCurlFailure: true)
        XCTAssertNotEqual(denied.exitCode, 0)
        XCTAssertTrue(denied.headers.contains("403"))
        wait(for: [upstreamTLS, scopedRejection], timeout: 2)
    }
}

private struct Reply {
    var body: Data
    var mime: String
    var encoding: String
    var fragment: Int
    var omitLength: Bool
    var delayMilliseconds: Int64
    init(_ body: Data, mime: String = "application/x-protobuf", encoding: String = "identity",
         fragment: Int = 16384, omitLength: Bool = false, delayMilliseconds: Int64 = 20) {
        self.body = body; self.mime = mime; self.encoding = encoding
        self.fragment = fragment; self.omitLength = omitLength
        self.delayMilliseconds = delayMilliseconds
    }
}

private final class FixtureHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    let reply: (HTTPRequestHead) -> Reply
    var head: HTTPRequestHead?
    init(_ reply: @escaping (HTTPRequestHead) -> Reply) { self.reply = reply }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head): self.head = head
        case .body: break
        case .end:
            let response = reply(head!)
            var headers = HTTPHeaders([("content-type", response.mime), ("content-encoding", response.encoding), ("etag", "synthetic")])
            if !response.omitLength { headers.add(name: "content-length", value: String(response.body.count)) }
            context.channel.write(HTTPServerResponsePart.head(.init(version: .http1_1, status: .ok, headers: headers)), promise: nil)
            // Flush a tiny prefix separately: it cannot be mistaken for a complete UMP program.
            let split = min(response.fragment, response.body.count)
            if split > 0 { context.channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(context.channel.allocator.buffer(bytes: response.body.prefix(split)))), promise: nil) }
            context.eventLoop.scheduleTask(in: .milliseconds(response.delayMilliseconds)) {
                for offset in stride(from: split, to: response.body.count, by: max(response.fragment, 4096)) {
                    let end = min(offset + max(response.fragment, 4096), response.body.count)
                    context.channel.write(HTTPServerResponsePart.body(.byteBuffer(context.channel.allocator.buffer(bytes: response.body[offset..<end]))), promise: nil)
                }
                context.channel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in context.close(promise: nil) }
            }
        }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}

private final class Lab {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let directory: URL
    let upstream: Channel
    let proxy: ProxyServer
    let port: Int
    let publicDER: Data

    init(trustUpstream: Bool = true, servesCertificate: Bool = false,
         log: @escaping (String) -> Void = { _ in }, reply: @escaping (HTTPRequestHead) -> Reply) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("localfilter-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let pair = try CertificateAuthority.generate()
        let authority = try CertificateAuthority(certificatePEM: pair.certificatePEM, privateKeyPEM: pair.privateKeyPEM)
        publicDER = try authority.certificateDER()
        try Data(pair.certificatePEM.utf8).write(to: directory.appendingPathComponent("ca.pem"))
        // Each CONNECT hostname needs its own certificate on the synthetic upstream.
        // A media/API wildcard is unnecessary: the proxy checks API and media names separately below.
        let apiTLS = try authority.serverContext(host: "youtubei.googleapis.com")
        let mediaTLS = try authority.serverContext(host: "rr1.googlevideo.com")
        // Use SNI to select the test certificate through the supported NIOSSL callback.
        var tls = apiTLS.configuration
        tls.sslContextCallback = { hello, promise in
            let selected = hello.serverHostname == "rr1.googlevideo.com" ? mediaTLS.configuration : apiTLS.configuration
            var override = NIOSSLContextConfigurationOverride()
            override.certificateChain = selected.certificateChain
            override.privateKey = selected.privateKey
            promise.succeed(override)
        }
        let context = try NIOSSLContext(configuration: tls)
        upstream = try ServerBootstrap(group: group).childChannelInitializer { channel in
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: context))
            }.flatMap { channel.pipeline.configureHTTPServerPipeline() }
                .flatMapThrowing { try channel.pipeline.syncOperations.addHandler(FixtureHandler(reply)) }
        }.bind(host: "127.0.0.1", port: 0).wait()
        var configuration = ProxyConfiguration(); configuration.port = 0
        configuration.servesCertificate = servesCertificate
        configuration.testUpstream = upstream.localAddress
        if trustUpstream { configuration.testTrustRoots = .certificates(try NIOSSLCertificate.fromPEMBytes(Array(pair.certificatePEM.utf8))) }
        proxy = try ProxyServer(configuration: configuration, authority: authority, log: log)
        port = try proxy.start()
    }

    func stop() {
        try? proxy.stop(); try? upstream.close().wait(); try? group.syncShutdownGracefully()
        try? FileManager.default.removeItem(at: directory)
    }

    func fetch(_ url: String, body: Data? = nil, headers: [String] = [], allowCurlFailure: Bool = false,
               maxTime: Double = 15, useProxy: Bool = true) throws -> (body: Data, headers: String, status: Int, exitCode: Int32) {
        let name = UUID().uuidString
        let output = directory.appendingPathComponent(name), header = directory.appendingPathComponent(name + ".headers")
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args = ["--silent", "--show-error", "--max-time", String(maxTime), "--http1.1", "--noproxy", useProxy ? "" : "*",
                    "--proxy", "http://127.0.0.1:\(port)", "--cacert", directory.appendingPathComponent("ca.pem").path,
                    "--output", output.path, "--dump-header", header.path]
        for value in headers { args += ["--header", value] }
        if let body {
            let file = directory.appendingPathComponent(name + ".request"); try body.write(to: file)
            args += ["--data-binary", "@" + file.path]
        }
        task.arguments = args + [url]; task.standardError = FileHandle.nullDevice; task.standardOutput = FileHandle.nullDevice
        try task.run(); task.waitUntilExit()
        if !allowCurlFailure { XCTAssertEqual(task.terminationStatus, 0) }
        let text = (try? String(contentsOf: header, encoding: .utf8)) ?? ""
        let statuses = text.components(separatedBy: "\r\n").filter { $0.hasPrefix("HTTP/") }
        let status = statuses.last.flatMap { Int($0.split(separator: " ").dropFirst().first ?? "") } ?? 0
        return ((try? Data(contentsOf: output)) ?? Data(), text, status, task.terminationStatus)
    }
}
