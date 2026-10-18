import Foundation
import NIOCore
import LocalFilterCore

enum DestinationPolicy {
    static func isTarget(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { return false }
        return ResponseProcessor.isAPIHost(host) || ResponseProcessor.isMediaHost(host)
    }

    static func authority(_ value: String) -> String? {
        let parts = value.lowercased().split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1] == "443", isTarget(String(parts[0])) else { return nil }
        return String(parts[0])
    }

    static func isPublic(_ address: SocketAddress) -> Bool {
        guard let ip = address.ipAddress else { return false }
        if ip.contains(":") {
            // Global unicast only; excludes mapped IPv4, local, multicast and documentation addresses.
            guard let first = ip.split(separator: ":").first.flatMap({ UInt16($0, radix: 16) }),
                  first & 0xe000 == 0x2000 else { return false }
            return !ip.hasPrefix("2001:db8:") && !ip.hasPrefix("2001:0:") && !ip.hasPrefix("2002:")
        }
        let octets = ip.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        let a = octets[0], b = octets[1], c = octets[2]
        return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
                 (a == 100 && (64...127).contains(b)) || (a == 169 && b == 254) ||
                 (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) ||
                 (a == 192 && b == 0) || (a == 192 && b == 88 && c == 99) ||
                 (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) ||
                 (a == 203 && b == 0 && c == 113))
    }

    static func resolve(_ host: String, on loop: EventLoop) -> EventLoopFuture<SocketAddress> {
        let promise = loop.makePromise(of: SocketAddress.self)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let address = try SocketAddress.makeAddressResolvingHost(host, port: 443)
                guard isTarget(host), isPublic(address) else { throw TransportError.destinationDenied }
                // Connect to this exact checked address, without a second DNS lookup.
                promise.succeed(address)
            } catch { promise.fail(error) }
        }
        return promise.futureResult
    }
}
