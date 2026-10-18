import Foundation

enum ConnectionMode: String, Codable {
    case setup, filter
}

struct TunnelStatus: Codable {
    var mode: ConnectionMode
    var certificateURL: String
    var responses = 0
    var rewrittenResponses = 0
    var upstreamFailures = 0
    var cancellations = 0
    var lastActivity: Date?

    mutating func record(_ event: String) {
        if event.hasPrefix("response ") {
            responses += 1
            if event.hasSuffix("modified=true") { rewrittenResponses += 1 }
            lastActivity = Date()
        } else if event.hasPrefix("upstream_failed ") { upstreamFailures += 1 }
        else if event.hasPrefix("request_cancelled ") { cancellations += 1 }
    }
}
