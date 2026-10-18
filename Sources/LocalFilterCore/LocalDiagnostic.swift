import Foundation

public struct DiagnosticResult: Sendable {
    public let passed: Bool
    public let removedFieldCount: Int
    public let mediaUnchanged: Bool
}

public enum LocalDiagnostic {
    /// Synthetic data only. This checks the engine, not YouTube or a VPN connection.
    public static func run() -> DiagnosticResult {
        let clean = Wire.field(2, Data()) + Wire.field(11, Wire.field(1, Data("demoVideo01".utf8)))
            + Wire.field(777, Data("unknown preserved".utf8))
        let player = clean + Wire.field(7, Data("synthetic instruction".utf8))
            + Wire.field(68, Data("synthetic slot".utf8))
        let api = AdProgramRewriter.rewriteAPI(player, path: "/youtubei/v1/player", enabled: true)
        let header = Wire.integer(1, 0) + Wire.field(4, Data())
        let envelope = Wire.integer(1, 1) + Wire.integer(2, 200) + Wire.field(4, player)
        let media = UMP.part(12, Data(repeating: 0xa5, count: 4096))
        let input = UMP.part(10, header) + UMP.part(11, envelope) + media
        let stream = AdProgramStream(enabled: true)
        var output = Data()
        for byte in input { output += stream.feed(Data([byte])) }
        output += stream.finish()
        let unchanged = output.suffix(media.count) == media
        let expected = UMP.part(10, header)
            + UMP.part(11, Wire.integer(1, 1) + Wire.integer(2, 200) + Wire.field(4, clean)) + media
        return DiagnosticResult(passed: api.data == clean && output == expected && stream.modified,
                                removedFieldCount: api.reports.flatMap { $0.adFields.values }.reduce(0, +),
                                mediaUnchanged: unchanged)
    }
}
