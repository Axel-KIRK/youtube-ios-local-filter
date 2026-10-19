import Foundation

enum ConnectionMode: String, Codable {
    case setup, filter
}

struct TunnelStatus: Codable {
    var mode: ConnectionMode
    var certificateURL: String
    var certificateID: String?
    var certificateServedAt: Date?
    var responses = 0
    var rewrittenResponses = 0
    var upstreamFailures = 0
    var cancellations = 0
    var connections = 0
    var connectRequests = 0
    var decryptedRequests = 0
    var downstreamFailures = 0
    var rejections = 0
    var lastFailure: String?
    var lastActivity: Date?

    mutating func record(_ event: String) {
        if event == "certificate_served" { certificateServedAt = Date() }
        if event == "connection_accepted" { connections += 1 }
        else if event == "connect_accepted" { connectRequests += 1 }
        else if event == "request_received" { decryptedRequests += 1 }
        else if event.hasPrefix("downstream_failed ") { downstreamFailures += 1 }
        else if event.hasPrefix("connection_rejected ") || event.hasPrefix("connect_rejected ") { rejections += 1 }
        if event.contains("_failed ") || event.contains("_rejected ") {
            let kind = String(event.split(separator: " ").first ?? "transport")
            // Whitelist reason codes: status and OS logs must not retain request data.
            let allowed = ["client", "capacity", "destination_or_request", "certificate_setup", "http_request",
                           "response_timeout", "tls_handshake", "tls_closed", "tls", "socket", "dns",
                           "connect_timeout", "destination_or_transport", "transport", "closed"]
            let reason = event.split(separator: " ").first(where: { $0.hasPrefix("reason=") })
                .map { String($0.dropFirst(7)) } ?? "transport"
            lastFailure = kind + ": " + (allowed.contains(reason) ? reason : "transport")
        }
        if event.hasPrefix("response ") {
            responses += 1
            if event.hasSuffix("modified=true") { rewrittenResponses += 1 }
            lastActivity = Date()
        } else if event.hasPrefix("upstream_failed ") { upstreamFailures += 1 }
        else if event.hasPrefix("request_cancelled ") { cancellations += 1 }
    }
}
