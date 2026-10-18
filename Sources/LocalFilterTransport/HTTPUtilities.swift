import Foundation
import NIOHTTP1
import CLocalCompression

enum HTTPUtilities {
    static let bodyLimit = 4 * 1024 * 1024

    static func clean(_ input: HTTPHeaders) -> HTTPHeaders {
        var headers = input
        let named = input[canonicalForm: "connection"]
        for name in named { headers.remove(name: String(name)) }
        for name in ["connection", "proxy-connection", "proxy-authorization", "proxy-authenticate",
                     "keep-alive", "te", "trailer", "transfer-encoding", "upgrade",
                     "alt-svc",
                     "x-poc-client-ip", "x-poc-flow-id"] { headers.remove(name: name) }
        return headers
    }

    static func invalidateRepresentation(_ headers: inout HTTPHeaders) {
        for name in ["content-length", "content-md5", "digest", "etag", "content-range"] {
            headers.remove(name: name)
        }
    }

    static func decoded(_ input: Data, encoding: String) -> Data? {
        if encoding == "identity" || encoding.isEmpty { return input }
        guard encoding == "gzip", input.count <= bodyLimit else { return nil }
        var output = Data(count: bodyLimit + 1), written = bodyLimit + 1
        let status = output.withUnsafeMutableBytes { target in
            input.withUnsafeBytes { source in
                lf_gunzip(source.bindMemory(to: UInt8.self).baseAddress, input.count,
                          target.bindMemory(to: UInt8.self).baseAddress, &written)
            }
        }
        guard status == 0, written <= bodyLimit else { return nil }
        output.count = written
        return output
    }
}
