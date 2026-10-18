import Foundation

/// Adapter used by the HTTPS transport. Does not open sockets or configure a VPN itself.
public final class ResponseProcessor {
    public let vault = OnesieKeyVault()
    public var enabled: Bool
    public init(enabled: Bool = false) { self.enabled = enabled }

    public static func isAPIHost(_ host: String) -> Bool {
        ["youtubei.googleapis.com", "youtubei-att.googleapis.com"].contains(host.lowercased())
    }
    public static func isMediaHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
    }

    public func needsFreshConfiguration(host: String, path: String, client: String) -> Bool {
        Self.isAPIHost(host) && path == "/youtubei/v1/log_event" && !vault.ready(client: client)
    }

    public func prepareRequest(host: String, path: String, body: Data, client: String) {
        if Self.isMediaHost(host), path == "/initplayback" {
            vault.invalidateIfUnknownRequest(body, client: client)
        }
    }

    public func processAPI(_ body: Data, host: String, path: String, client: String) -> RewriteResult {
        guard Self.isAPIHost(host) else {
            return RewriteResult(data: body, reports: [], modified: false, recognized: false)
        }
        if path == "/youtubei/v1/log_event" { vault.capture(body, client: client) }
        return AdProgramRewriter.rewriteAPI(body, path: path, enabled: enabled)
    }

    public func makeStream(host: String, path: String, contentType: String,
                           contentEncoding: String = "identity", requestBody: Data,
                           client: String) -> AdProgramStream? {
        let mime = contentType.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces).lowercased()
        guard Self.isMediaHost(host), path == "/initplayback", mime == "application/vnd.yt-ump",
              contentEncoding.lowercased() == "identity" else { return nil }
        return AdProgramStream(key: vault.keyForRequest(requestBody, client: client), enabled: enabled)
    }
}
