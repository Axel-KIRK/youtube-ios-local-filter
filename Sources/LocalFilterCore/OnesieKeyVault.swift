import Foundation
import CryptoKit

/// Ephemeral keys only. Own this object on the same serial executor as the HTTP adapter.
public final class OnesieKeyVault {
    private struct Identity: Hashable { let client: String; let digest: Data }
    private struct Entry { let key: Data; let expires: Date; let sequence: UInt64 }
    private var entries = [Identity: Entry]()
    private var sequence: UInt64 = 0

    public init() {}
    public var entryCount: Int { entries.count }
    public func clear() { entries.removeAll() }

    /// A new wrapped key can appear after YouTube restarts while its hot-config hash is unchanged.
    public func invalidateIfUnknownRequest(_ body: Data, client: String, now: Date = Date()) {
        guard body.count <= 1024 * 1024,
              let envelope = try? Wire.child(body, 3),
              let wrapped = try? Wire.child(envelope, 5), (16...1024).contains(wrapped.count),
              keyForRequest(body, client: client, now: now) == nil else { return }
        entries = entries.filter { $0.key.client != client }
    }

    public func ready(client: String, now: Date = Date()) -> Bool {
        entries = entries.filter { $0.value.expires > now }
        return entries.contains { $0.key.client == client }
    }

    @discardableResult
    public func capture(_ body: Data, client: String, now: Date = Date()) -> Bool {
        do {
            guard let context = try Wire.child(body, 1), let group = try Wire.child(context, 16) else { return false }
            let fields = try Wire.parse(group)
            var hot = try Wire.one(fields, 7, 2)?.bytes
            if hot == nil, let encoded = try Wire.one(fields, 3, 2)?.bytes,
               var text = String(data: encoded, encoding: .ascii) {
                text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                text += String(repeating: "=", count: (4 - text.count % 4) % 4)
                hot = Data(base64Encoded: text)
            }
            guard let media = try Wire.child(hot, 138536474),
                  let config = try Wire.child(media, 146311580) else { return false }
            let values = try Wire.parse(config)
            guard let key = try Wire.one(values, 1, 2)?.bytes, key.count == 32,
                  let wrapped = try Wire.one(values, 2, 2)?.bytes, (16...1024).contains(wrapped.count) else { return false }
            let rawTTL = try Wire.one(values, 3, 0)?.integer ?? 1800
            let ttl = min(rawTTL == 0 ? 1800 : rawTTL, 3600)
            let identity = Identity(client: client, digest: Data(SHA256.hash(data: wrapped)))
            entries = entries.filter { $0.value.expires > now }
            sequence &+= 1
            entries[identity] = Entry(key: key, expires: now.addingTimeInterval(Double(ttl)), sequence: sequence)
            if entries.count > 32, let oldest = entries.min(by: { $0.value.sequence < $1.value.sequence })?.key {
                entries.removeValue(forKey: oldest)
            }
            return true
        } catch { return false }
    }

    public func keyForRequest(_ body: Data, client: String, now: Date = Date()) -> Data? {
        do {
            guard body.count <= 1024 * 1024,
                  let envelope = try Wire.child(body, 3), let wrapped = try Wire.child(envelope, 5) else { return nil }
            let identity = Identity(client: client, digest: Data(SHA256.hash(data: wrapped)))
            guard let entry = entries[identity], entry.expires > now else { return nil }
            return entry.key
        } catch { return nil }
    }
}
