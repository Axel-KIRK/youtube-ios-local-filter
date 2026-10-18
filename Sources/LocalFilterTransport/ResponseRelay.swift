import Foundation
import NIOCore
import NIOHTTP1
import LocalFilterCore

final class ResponseRelay: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    let server: ProxyServer
    let downstream: Channel
    let host: String
    let path: String
    let client: String
    let request: HTTPRequestHead
    let requestBody: Data
    let receivedHeaders: () -> Void
    let completed: () -> Void
    var head: HTTPResponseHead?
    var buffer = Data()
    var buffered = false
    var stream: AdProgramStream?
    var sentHead = false
    var done = false
    var modified = false

    init(server: ProxyServer, downstream: Channel, host: String, path: String, client: String,
         request: HTTPRequestHead, requestBody: Data, receivedHeaders: @escaping () -> Void,
         completed: @escaping () -> Void) {
        self.server = server; self.downstream = downstream; self.host = host; self.path = path
        self.client = client; self.request = request; self.requestBody = requestBody; self.completed = completed
        self.receivedHeaders = receivedHeaders
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !done else { return }
        switch unwrapInboundIn(data) {
        case .head(var head):
            if (100..<200).contains(head.status.code) {
                if head.status.code == 101 { fail() }
                return
            }
            head.version = .http1_1
            receivedHeaders()
            head.headers = HTTPUtilities.clean(head.headers)
            if request.method == .HEAD && !head.headers.contains(name: "content-length") {
                head.headers.add(name: "content-length", value: "0")
            }
            self.head = head
            let successful = (200..<300).contains(head.status.code) && head.status.code != 204 && request.method != .HEAD
            buffered = successful && ResponseProcessor.isAPIHost(host) &&
                ["/youtubei/v1/player", "/youtubei/v1/get_watch", "/youtubei/v1/log_event"].contains(path) &&
                (Int(head.headers.first(name: "content-length") ?? "0") ?? Int.max) <= HTTPUtilities.bodyLimit
            if successful {
                stream = server.processor.makeStream(host: host, path: path,
                    contentType: head.headers.first(name: "content-type") ?? "",
                    contentEncoding: head.headers.first(name: "content-encoding")?.lowercased() ?? "identity",
                    requestBody: requestBody, client: client)
            }
            if stream != nil { HTTPUtilities.invalidateRepresentation(&self.head!.headers) }
            if !buffered { sendHead() }
        case .body(var bytes):
            let data = Data(bytes.readBytes(length: bytes.readableBytes) ?? [])
            if buffered && buffer.count + data.count <= HTTPUtilities.bodyLimit { buffer.append(data) }
            else {
                if buffered {
                    // Oversized or unknown responses stay byte-identical and stream without further buffering.
                    buffered = false; sendHead(); write(buffer); buffer.removeAll(keepingCapacity: false)
                }
                write(stream?.feed(data) ?? data)
                recordStreamEvents()
            }
        case .end:
            if buffered, let head {
                let encoding = head.headers.first(name: "content-encoding")?.lowercased() ?? "identity"
                if let clear = HTTPUtilities.decoded(buffer, encoding: encoding) {
                    let result = server.processor.processAPI(clear, host: host, path: path, client: client)
                    if result.modified {
                        buffer = result.data; modified = true
                        HTTPUtilities.invalidateRepresentation(&self.head!.headers)
                        self.head!.headers.remove(name: "content-encoding")
                        self.head!.headers.replaceOrAdd(name: "content-length", value: String(buffer.count))
                    }
                }
                sendHead(); write(buffer); buffer.removeAll(keepingCapacity: false)
            }
            write(stream?.finish() ?? Data()); recordStreamEvents()
            guard sentHead else { fail(); return }
            done = true
            downstream.writeAndFlush(HTTPServerResponsePart.end(nil)).whenFailure { _ in self.downstream.close(promise: nil) }
            server.log("response host=\(host) path=\(safePath) status=\(head?.status.code ?? 0) modified=\(modified)")
            completed()
            context.close(promise: nil)
        }
    }

    private var safePath: String {
        ["/youtubei/v1/player", "/youtubei/v1/get_watch", "/youtubei/v1/log_event", "/initplayback", "/videoplayback"].contains(path) ? path : "[other]"
    }

    private func sendHead() {
        guard !sentHead, let head else { return }
        sentHead = true
        // NIO chooses chunked framing when the response can have a body but has no Content-Length.
        downstream.write(HTTPServerResponsePart.head(head), promise: nil)
    }

    private func write(_ data: Data) {
        guard !data.isEmpty else { return } // An empty transformed fragment is never end-of-response.
        downstream.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(downstream.allocator.buffer(bytes: data))), promise: nil)
    }

    private func recordStreamEvents() {
        for event in stream?.drainEvents() ?? [] {
            modified = modified || event.modified
            server.log("program recognized=\(event.recognized) modified=\(event.modified) players=\(event.players.count)")
        }
    }

    func fail() {
        guard !done else { return }
        done = true; completed()
        server.log("upstream_failed host=\(host) path=\(safePath)")
        if sentHead { downstream.close(promise: nil) }
        else { sendError(downstream, status: .badGateway) }
    }
    func channelInactive(context: ChannelHandlerContext) { if !done { fail() } }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is IdleStateHandler.IdleStateEvent { fail(); context.close(promise: nil) }
        else { context.fireUserInboundEventTriggered(event) }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { fail(); context.close(promise: nil) }
}
