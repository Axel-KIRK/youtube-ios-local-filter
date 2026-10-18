import Foundation

public struct PlayerReport: Equatable, Sendable {
    public let videoID: String
    public let adFields: [String: Int]
    public let removed: Bool
}

public struct RewriteResult: Sendable {
    public let data: Data
    public let reports: [PlayerReport]
    public let modified: Bool
    public let recognized: Bool
}

struct PairResult {
    var header: Data
    var body: Data
    var reports: [PlayerReport] = []
    var recognized = false
}

public enum AdProgramRewriter {
    static let adFields: [UInt32: String] = [7: "playerAds", 45: "adPlacements", 68: "adSlots"]

    public static func rewriteAPI(_ data: Data, path: String, enabled: Bool) -> RewriteResult {
        var reports = [PlayerReport]()
        do {
            let rewritten: Data
            switch path {
            case "/youtubei/v1/player": rewritten = try player(data, enabled, &reports)
            case "/youtubei/v1/get_watch":
                rewritten = try Wire.transform(data, field: 1) { try watch($0, enabled, &reports) }
            default: return RewriteResult(data: data, reports: [], modified: false, recognized: false)
            }
            return RewriteResult(data: rewritten, reports: reports,
                                 modified: rewritten != data, recognized: !reports.isEmpty)
        } catch {
            // Atomic fallback: do not claim that partially processed fields were removed.
            return RewriteResult(data: data, reports: [], modified: false, recognized: false)
        }
    }

    static func player(_ data: Data, _ enabled: Bool, _ reports: inout [PlayerReport]) throws -> Data {
        let fields = try Wire.parse(data)
        guard let details = try Wire.one(fields, 11, 2)?.bytes,
              let idData = try Wire.child(details, 1),
              idData.count == 11,
              idData.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                               || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
              let id = String(data: idData, encoding: .ascii),
              fields.contains(where: { [2, 4].contains($0.number) && $0.kind == 2 }) else { return data }
        var counts = [String: Int]()
        for f in fields where f.kind == 2 {
            if let name = adFields[f.number] { counts[name, default: 0] += 1 }
        }
        reports.append(PlayerReport(videoID: id, adFields: counts, removed: enabled && !counts.isEmpty))
        guard enabled && !counts.isEmpty else { return data }
        return fields.reduce(into: Data()) { output, f in
            if f.kind != 2 || adFields[f.number] == nil { output += f.raw }
        }
    }

    static func watch(_ data: Data, _ enabled: Bool, _ reports: inout [PlayerReport]) throws -> Data {
        try Wire.transform(data, field: 2) { try player($0, enabled, &reports) }
    }

    static func rewritePair(header: Data, body: Data, key: Data?, enabled: Bool) -> PairResult {
        let original = PairResult(header: header, body: body)
        do {
            guard header.count <= Wire.limit, body.count <= Wire.limit else { return original }
            let fields = try Wire.parse(header)
            let kind = try Wire.one(fields, 1, 0)?.integer ?? 0
            guard kind == 0 || kind == 25 else { return original }
            let params: Data
            if kind == 25 { params = body }
            else {
                guard let value = try Wire.one(fields, 4, 2)?.bytes else { return original }
                params = value
            }
            let crypto = try Wire.parse(params)
            let tag = try Wire.one(crypto, kind == 25 ? 2 : 4, 2)?.bytes ?? Data()
            let iv = try Wire.one(crypto, kind == 25 ? 3 : 5, 2)?.bytes ?? Data()
            let compression = try Wire.one(crypto, kind == 25 ? 4 : 6, 0)?.integer ?? 0
            let clear = kind == 0 && tag.isEmpty && iv.isEmpty
            let cipher: Data
            if kind == 25 {
                guard let value = try Wire.one(crypto, 1, 2)?.bytes else { return original }
                cipher = value
            } else { cipher = body }
            let decoded: Data
            if clear { decoded = cipher }
            else {
                guard let key, OnesieCrypto.authenticated(cipher, iv: iv, tag: tag, key: key) else { return original }
                decoded = try OnesieCrypto.crypt(cipher, key: key, iv: iv)
            }
            let plain = try OnesieCrypto.decode(decoded, compression: compression)
            let envelope = try Wire.parse(plain)
            let state = try Wire.one(envelope, 1, 0)?.integer
            let status = try Wire.one(envelope, 2, 0)?.integer
            guard (state == 1 || (kind == 25 && state == nil)),
                  (status == 200 || (kind == 25 && status == nil)) else { return original }
            var reports = [PlayerReport]()
            let rewritten = try Wire.transform(plain, field: 4) {
                kind == 25 ? try watch($0, enabled, &reports) : try player($0, enabled, &reports)
            }
            guard rewritten != plain else {
                return PairResult(header: header, body: body, reports: reports, recognized: true)
            }
            let encoded = try OnesieCrypto.encode(rewritten, compression: compression)
            if clear { return PairResult(header: header, body: encoded, reports: reports, recognized: true) }
            guard let key else { return original }
            let newIV = try OnesieCrypto.randomIV()
            let encrypted = try OnesieCrypto.crypt(encoded, key: key, iv: newIV)
            let newTag = OnesieCrypto.tag(encrypted, iv: newIV, key: key)
            if kind == 25 {
                var out = try Wire.transform(body, field: 1) { _ in encrypted }
                out = try Wire.transform(out, field: 2) { _ in newTag }
                out = try Wire.transform(out, field: 3) { _ in newIV }
                return PairResult(header: header, body: out, reports: reports, recognized: true)
            }
            var out = try Wire.transform(params, field: 4) { _ in newTag }
            out = try Wire.transform(out, field: 5) { _ in newIV }
            let newHeader = try Wire.transform(header, field: 4) { _ in out }
            return PairResult(header: newHeader, body: encrypted, reports: reports, recognized: true)
        } catch { return original }
    }
}
