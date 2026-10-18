import Foundation

enum UMP {
    static func read(_ input: [UInt8], at offset: Int = 0) -> (UInt32, Int)? {
        guard offset < input.count else { return nil }
        let first = input[offset]
        let length = first < 128 ? 1 : first < 192 ? 2 : first < 224 ? 3 : first < 240 ? 4 : 5
        guard input.count - offset >= length else { return nil }
        if length == 1 { return (UInt32(first), offset + 1) }
        var tail: UInt32 = 0
        for i in 1..<length { tail |= UInt32(input[offset + i]) << ((i - 1) * 8) }
        if length == 5 { return (tail, offset + 5) }
        let bits = 8 - length
        return (UInt32(first & UInt8((1 << bits) - 1)) | (tail << bits), offset + length)
    }

    static func uint(_ value: UInt32) -> Data {
        for length in 1...4 where UInt64(value) < (UInt64(1) << (7 * length)) {
            if length == 1 { return Data([UInt8(value)]) }
            let bits = 8 - length
            var bytes = Data([UInt8(truncatingIfNeeded: 0xff << (9 - length)) | UInt8(value & UInt32((1 << bits) - 1))])
            let tail = value >> bits
            for i in 0..<(length - 1) { bytes.append(UInt8(truncatingIfNeeded: tail >> (8 * i))) }
            return bytes
        }
        var bytes = Data([0xf0])
        for i in 0..<4 { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * i))) }
        return bytes
    }

    static func part(_ kind: UInt32, _ payload: Data) -> Data {
        uint(kind) + uint(UInt32(payload.count)) + payload
    }
}

public struct StreamEvent: Sendable {
    public let recognized: Bool
    public let modified: Bool
    public let players: [PlayerReport]
}

/// One instance per HTTP response. Use on a single serial executor.
/// Empty `feed` is not EOF; call `finish` only when the upstream really ends.
public final class AdProgramStream {
    private let key: Data?
    private let enabled: Bool
    private var prefix = [UInt8]()
    private var payload = Data()
    private var kind: UInt32?
    private var remaining = 0
    private var keep = false
    private var pending: (raw: Data, header: Data)?
    private var events = [StreamEvent]()
    private var finished = false
    public private(set) var modified = false
    public var bufferedByteCount: Int { prefix.count + payload.count + (pending?.raw.count ?? 0) }

    public init(key: Data? = nil, enabled: Bool) { self.key = key; self.enabled = enabled }

    public func drainEvents() -> [StreamEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    public func feed(_ data: Data) -> Data {
        guard !finished else { return data }
        let input = [UInt8](data)
        var offset = 0, output = Data()
        while offset < input.count {
            if kind == nil {
                prefix.append(input[offset]); offset += 1
                guard let first = UMP.read(prefix), let second = UMP.read(prefix, at: first.1) else { continue }
                kind = first.0; remaining = Int(second.0)
                keep = (kind == 10 || kind == 11) && remaining <= Wire.limit
                if let old = pending, kind != 11 || !keep { output += old.raw; pending = nil }
                if !keep { output += Data(prefix); prefix.removeAll(keepingCapacity: true) }
            }
            let count = min(remaining, input.count - offset)
            let fragment = input[offset..<(offset + count)]
            if keep { payload.append(contentsOf: fragment) } else { output.append(contentsOf: fragment) }
            offset += count; remaining -= count
            if remaining == 0 {
                if keep {
                    let raw = Data(prefix) + payload
                    if kind == 10 { pending = (raw, payload) }
                    else if let previous = pending {
                        let result = AdProgramRewriter.rewritePair(header: previous.header, body: payload,
                                                                   key: key, enabled: enabled)
                        let changed = result.header != previous.header || result.body != payload
                        if changed { output += UMP.part(10, result.header) + UMP.part(11, result.body) }
                        else { output += previous.raw + raw }
                        modified = modified || changed
                        // Bounded diagnostics, no keys, URLs, or decrypted payloads.
                        if events.count < 64 {
                            events.append(StreamEvent(recognized: result.recognized, modified: changed, players: result.reports))
                        }
                        pending = nil
                    } else { output += raw }
                }
                kind = nil; prefix.removeAll(keepingCapacity: true); payload.removeAll(keepingCapacity: true)
            }
        }
        return output
    }

    public func finish() -> Data {
        guard !finished else { return Data() }
        finished = true
        let output = (pending?.raw ?? Data()) + Data(prefix) + payload
        pending = nil; prefix.removeAll(); payload.removeAll()
        return output
    }
}
