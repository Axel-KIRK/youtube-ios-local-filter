import XCTest
@testable import LocalFilterCore

private struct Fixture: Decodable {
    let name: String
    let kind: Int
    let compressed: Bool
    let key, iv, input, originalPlain, expectedPlain, media: Data
}

final class OnesieTests: XCTestCase {
    private func fixtures() throws -> [Fixture] {
        let url = Bundle.module.url(forResource: "onesie", withExtension: "json", subdirectory: "Fixtures")!
        return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }
    private func parts(_ input: Data) throws -> [(UInt32, Data)] {
        let bytes = [UInt8](input)
        var cursor = 0, result = [(UInt32, Data)]()
        while cursor < bytes.count {
            guard let kind = UMP.read(bytes, at: cursor), let length = UMP.read(bytes, at: kind.1),
                  Int(length.0) <= bytes.count - length.1 else { throw DecodeError.malformed }
            result.append((kind.0, Data(bytes[length.1..<(length.1 + Int(length.0))])))
            cursor = length.1 + Int(length.0)
        }
        return result
    }
    private func decryptPair(_ input: Data, fixture: Fixture) throws -> (plain: Data, iv: Data) {
        let parts = try parts(input)
        let params = fixture.kind == 25 ? parts[1].1 : try XCTUnwrap(Wire.child(parts[0].1, 4))
        let tag = try XCTUnwrap(Wire.child(params, fixture.kind == 25 ? 2 : 4))
        let iv = try XCTUnwrap(Wire.child(params, fixture.kind == 25 ? 3 : 5))
        let cipher = fixture.kind == 25 ? try XCTUnwrap(Wire.child(params, 1)) : parts[1].1
        XCTAssertTrue(OnesieCrypto.authenticated(cipher, iv: iv, tag: tag, key: fixture.key))
        let decoded = try OnesieCrypto.crypt(cipher, key: fixture.key, iv: iv)
        return (try OnesieCrypto.decode(decoded, compression: fixture.compressed ? 1 : 0), iv)
    }

    func testPythonFixturesDecryptAndRewriteWithFreshAuthenticatedIV() throws {
        for fixture in try fixtures() {
            XCTAssertEqual(try decryptPair(fixture.input, fixture: fixture).plain, fixture.originalPlain)
            for step in [1, 7, 4096] {
                let stream = AdProgramStream(key: fixture.key, enabled: true)
                var output = Data()
                for offset in stride(from: 0, to: fixture.input.count, by: step) {
                    output += stream.feed(fixture.input.subdata(in: offset..<min(offset + step, fixture.input.count)))
                }
                output += stream.finish()
                let decoded = try decryptPair(output, fixture: fixture)
                XCTAssertEqual(decoded.plain, fixture.expectedPlain, fixture.name)
                XCTAssertNotEqual(decoded.iv, fixture.iv)
                XCTAssertEqual(output.suffix(fixture.media.count), fixture.media)
                XCTAssertTrue(stream.modified)
                XCTAssertEqual(stream.drainEvents().first?.players.first?.adFields,
                               ["playerAds": 2, "adPlacements": 1, "adSlots": 1])
                XCTAssertTrue(stream.drainEvents().isEmpty)
            }
        }
    }

    func testMissingKeyBadAuthenticationAndObservationPassThrough() throws {
        for fixture in try fixtures() {
            for (key, enabled) in [(Optional<Data>.none, true), (Data(repeating: 0xff, count: 32), true), (fixture.key, false)] {
                let stream = AdProgramStream(key: key, enabled: enabled)
                XCTAssertEqual(stream.feed(fixture.input) + stream.finish(), fixture.input)
                XCTAssertFalse(stream.modified)
            }
            let pieces = try parts(fixture.input)
            let truncated = UMP.part(10, pieces[0].1) + UMP.uint(11) + UMP.uint(UInt32(pieces[1].1.count)) + pieces[1].1.dropLast(3)
            let stream = AdProgramStream(key: fixture.key, enabled: true)
            XCTAssertEqual(stream.feed(truncated) + stream.finish(), truncated)
            XCTAssertFalse(stream.modified)
        }
    }

    func testGzipRejectsBombTrailingDataAndInvalidCompression() throws {
        let compressed = try OnesieCrypto.gzip(Data(repeating: 7, count: 2048), compress: true)
        XCTAssertThrowsError(try OnesieCrypto.gzip(compressed, compress: false, limit: 1024))
        XCTAssertThrowsError(try OnesieCrypto.gzip(compressed + Data([1]), compress: false))
        XCTAssertThrowsError(try OnesieCrypto.decode(Data(), compression: 99))
    }

    func testUMPBoundaryValues() {
        for n: UInt32 in [0, 127, 128, 16383, 16384, 2097151, 2097152, 268435455, 268435456, .max] {
            let bytes = [UInt8](UMP.uint(n))
            XCTAssertEqual(UMP.read(bytes)?.0, n)
            XCTAssertEqual(UMP.read(bytes)?.1, bytes.count)
            for length in 0..<bytes.count { XCTAssertNil(UMP.read(Array(bytes.prefix(length)))) }
        }
    }

    func testOversizedControlsAndUnpairedHeadersDoNotAccumulate() {
        let prefix = UMP.part(10, Wire.integer(1, 25)) + UMP.uint(11) + UMP.uint(UInt32(Wire.limit + 1))
        let stream = AdProgramStream(enabled: true)
        XCTAssertEqual(stream.feed(prefix), prefix)
        let media = Data(repeating: 1, count: 16384)
        for _ in 0..<16 {
            XCTAssertEqual(stream.feed(media), media)
            XCTAssertLessThan(stream.bufferedByteCount, 16)
        }
        XCTAssertEqual(stream.finish(), Data())
        let raw = UMP.part(10, Data([1, 2])) + UMP.part(20, Data([3, 4]))
        let other = AdProgramStream(enabled: true)
        XCTAssertEqual(other.feed(raw) + other.finish(), raw)
    }

    func testEmptyChunkIsNotEOFAndFinishIsIdempotent() throws {
        let f = try fixtures()[0]
        let stream = AdProgramStream(key: f.key, enabled: true)
        var out = stream.feed(f.input.prefix(5))
        XCTAssertEqual(stream.feed(Data()), Data())
        out += stream.feed(f.input.dropFirst(5)); out += stream.finish()
        XCTAssertTrue(stream.modified)
        XCTAssertEqual(try decryptPair(out, fixture: f).plain, f.expectedPlain)
        XCTAssertEqual(stream.finish(), Data())
    }
}
