import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
import LocalFilterCore

public struct ProxyConfiguration {
    public var host = "127.0.0.1"
    public var port = 8881
    public var allowedClients: Set<String> = ["127.0.0.1", "::1"]
    public var enabled = true
    public var maximumConnections = 32
    public init() {}
    // Only injectable by this module's tests; unavailable through the executable or public API.
    var testUpstream: SocketAddress?
    var testTrustRoots: NIOSSLTrustRoots?
}

/// HTTP CONNECT backend for the scoped YouTube hosts. Not a general-purpose forwarding proxy.
/// One event loop owns all connections, the key vault, and certificate cache.
public final class ProxyServer {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let configuration: ProxyConfiguration
    let authority: CertificateAuthority
    let processor: ResponseProcessor
    let upstreamTLS: NIOSSLContext
    let log: (String) -> Void
    private var listener: Channel?
    private var connections = [ObjectIdentifier: Channel]()

    public init(configuration: ProxyConfiguration, authority: CertificateAuthority,
                log: @escaping (String) -> Void = { _ in }) throws {
        self.configuration = configuration
        self.authority = authority
        self.processor = ResponseProcessor(enabled: configuration.enabled)
        self.log = log
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.minimumTLSVersion = .tlsv12
        tls.applicationProtocols = ["http/1.1"]
        if let roots = configuration.testTrustRoots { tls.trustRoots = roots }
        upstreamTLS = try NIOSSLContext(configuration: tls)
    }

    public func start() throws -> Int {
        let channel = try ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .childChannelOption(ChannelOptions.writeBufferWaterMark, value: .init(low: 32768, high: 65536))
            .childChannelInitializer { channel in
                guard let ip = channel.remoteAddress?.ipAddress,
                      self.configuration.allowedClients.contains(ip),
                      self.connections.count < self.configuration.maximumConnections else {
                    return channel.close()
                }
                let identifier = ObjectIdentifier(channel)
                self.connections[identifier] = channel
                channel.closeFuture.whenComplete { _ in self.connections.removeValue(forKey: identifier) }
                let decoder = ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                let encoder = HTTPResponseEncoder()
                return channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandlers(encoder, decoder,
                        ConnectHandler(server: self, decoder: decoder, encoder: encoder, client: ip))
                }
            }.bind(host: configuration.host, port: configuration.port).wait()
        listener = channel
        return channel.localAddress!.port!
    }

    public func waitUntilClosed() throws { try listener?.closeFuture.wait() }

    public func stop() throws {
        try listener?.close().wait()
        try group.next().submit {
            for channel in self.connections.values { channel.close(promise: nil) }
            self.processor.vault.clear()
        }.wait()
        try group.syncShutdownGracefully()
    }

    func destination(_ host: String, on loop: EventLoop) -> EventLoopFuture<SocketAddress> {
        if let address = configuration.testUpstream { return loop.makeSucceededFuture(address) }
        return DestinationPolicy.resolve(host, on: loop)
    }
}

private final class ConnectHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    let server: ProxyServer
    let decoder: ByteToMessageHandler<HTTPRequestDecoder>
    let encoder: HTTPResponseEncoder
    let client: String
    var host: String?
    var rejected = false

    init(server: ProxyServer, decoder: ByteToMessageHandler<HTTPRequestDecoder>,
         encoder: HTTPResponseEncoder, client: String) {
        self.server = server; self.decoder = decoder; self.encoder = encoder; self.client = client
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !rejected else { return }
        switch unwrapInboundIn(data) {
        case .head(let request):
            guard request.method == .CONNECT, host == nil,
                  let target = DestinationPolicy.authority(request.uri),
                  !request.headers.contains(name: "transfer-encoding"),
                  request.headers.first(name: "content-length").map({ $0 == "0" }) ?? true else {
                rejected = true
                sendError(context.channel, status: .forbidden)
                return
            }
            host = target
        case .body:
            rejected = true; sendError(context.channel, status: .badRequest)
        case .end:
            guard let host else { context.close(promise: nil); return }
            do {
                let ssl = NIOSSLServerHandler(context: try server.authority.serverContext(host: host))
                let connection = HTTPConnection(server: server, host: host, client: client)
                let channel = context.channel
                channel.write(HTTPServerResponsePart.head(.init(version: .http1_1, status: .ok,
                    headers: HTTPHeaders([("Content-Length", "0")]))), promise: nil)
                channel.writeAndFlush(HTTPServerResponsePart.end(nil)).flatMap {
                    channel.pipeline.syncOperations.removeHandler(self.encoder)
                }.flatMapThrowing {
                    try channel.pipeline.syncOperations.addHandler(ssl, position: .after(self.decoder))
                    try channel.pipeline.syncOperations.addHandlers(HTTPResponseEncoder(),
                        ByteToMessageHandler(HTTPRequestDecoder()), connection, position: .after(ssl))
                }.flatMap {
                    channel.pipeline.removeHandler(self)
                }.flatMap {
                    // The old decoder forwards any bytes pipelined after CONNECT through TLS.
                    channel.pipeline.syncOperations.removeHandler(self.decoder)
                }.whenFailure { _ in channel.close(promise: nil) }
            } catch { rejected = true; sendError(context.channel, status: .internalServerError) }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}

func sendError(_ channel: Channel, status: HTTPResponseStatus) {
    let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
    channel.write(HTTPServerResponsePart.head(.init(version: .http1_1, status: status, headers: headers)), promise: nil)
    channel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in channel.close(promise: nil) }
}

private final class HTTPConnection: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    let server: ProxyServer
    let host: String
    let client: String
    var request: HTTPRequestHead?
    var body = Data()
    var active = false
    var upstream: Channel?
    var deadline: Scheduled<Void>?

    init(server: ProxyServer, host: String, client: String) {
        self.server = server; self.host = host; self.client = client
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            guard !active, request == nil, head.version == .http1_1,
                  head.method != .CONNECT, head.uri.hasPrefix("/"), !head.uri.hasPrefix("//"),
                  let authority = head.headers.first(name: "host")?.lowercased(),
                  authority == host || authority == host + ":443" else {
                sendError(context.channel, status: .badRequest); return
            }
            request = head
            if head.headers.first(name: "expect")?.lowercased() == "100-continue" {
                context.channel.writeAndFlush(HTTPServerResponsePart.head(.init(version: .http1_1, status: .continue)), promise: nil)
            }
        case .body(var bytes):
            guard request != nil, body.count + bytes.readableBytes <= HTTPUtilities.bodyLimit else {
                sendError(context.channel, status: .payloadTooLarge); return
            }
            body.append(contentsOf: bytes.readBytes(length: bytes.readableBytes) ?? [])
        case .end:
            guard var request, !active else { sendError(context.channel, status: .badRequest); return }
            active = true
            let channel = context.channel
            let path = String(request.uri.split(separator: "?", maxSplits: 1).first ?? "")
            let requestBody = HTTPUtilities.decoded(body, encoding: request.headers.first(name: "content-encoding")?.lowercased() ?? "identity") ?? Data()
            server.processor.prepareRequest(host: host, path: path, body: requestBody, client: client)
            request.headers = HTTPUtilities.clean(request.headers)
            request.headers.remove(name: "expect")
            request.headers.replaceOrAdd(name: "host", value: host)
            request.headers.replaceOrAdd(name: "content-length", value: String(body.count))
            request.headers.replaceOrAdd(name: "connection", value: "close")
            request.headers.replaceOrAdd(name: "accept-encoding", value: "identity")
            if server.processor.needsFreshConfiguration(host: host, path: path, client: client) {
                request.headers.remove(name: "x-youtube-hot-hash-data")
            }
            let upstreamRequest = request
            let upstreamBody = body
            body.removeAll(keepingCapacity: false)
            let relay = ResponseRelay(server: server, downstream: channel, host: host, path: path,
                                      client: client, request: upstreamRequest, requestBody: requestBody,
                                      receivedHeaders: { [weak self] in self?.deadline?.cancel(); self?.deadline = nil }) { [weak self] in
                self?.deadline?.cancel(); self?.deadline = nil
                self?.active = false; self?.request = nil; self?.upstream = nil
            }
            deadline = channel.eventLoop.scheduleTask(in: .seconds(60)) {
                relay.fail(); self.upstream?.close(promise: nil)
            }
            server.destination(host, on: channel.eventLoop).flatMap { address -> EventLoopFuture<Channel> in
                guard channel.isActive else { return channel.eventLoop.makeFailedFuture(TransportError.upstreamClosed) }
                return ClientBootstrap(group: channel.eventLoop)
                    .connectTimeout(.seconds(15))
                    .channelInitializer { upstream in
                        do {
                            let ssl = try NIOSSLClientHandler(context: self.server.upstreamTLS, serverHostname: self.host)
                            try upstream.pipeline.syncOperations.addHandler(ssl)
                            return upstream.pipeline.addHTTPClientHandlers().flatMapThrowing {
                                try upstream.pipeline.syncOperations.addHandlers(IdleStateHandler(readTimeout: .seconds(60)), relay)
                            }
                        } catch { return upstream.eventLoop.makeFailedFuture(error) }
                    }.connect(to: address)
            }.whenComplete { result in
                switch result {
                case .success(let upstream):
                    guard channel.isActive, self.active else { upstream.close(promise: nil); return }
                    self.upstream = upstream
                    upstream.write(HTTPClientRequestPart.head(upstreamRequest), promise: nil)
                    if !upstreamBody.isEmpty {
                        upstream.write(HTTPClientRequestPart.body(.byteBuffer(upstream.allocator.buffer(bytes: upstreamBody))), promise: nil)
                    }
                    upstream.writeAndFlush(HTTPClientRequestPart.end(nil)).whenFailure { _ in relay.fail() }
                case .failure: relay.fail()
                }
            }
        }
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        upstream?.setOption(ChannelOptions.autoRead, value: context.channel.isWritable).whenFailure { _ in
            context.close(promise: nil)
        }
        context.fireChannelWritabilityChanged()
    }

    func channelInactive(context: ChannelHandlerContext) {
        deadline?.cancel(); upstream?.close(promise: nil)
        context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}
