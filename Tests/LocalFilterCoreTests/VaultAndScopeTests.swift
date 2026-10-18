import XCTest
@testable import LocalFilterCore

final class VaultAndScopeTests: XCTestCase {
    private func config(_ wrapped: Data, ttl: UInt64 = 5, base64: Bool = false) -> Data {
        let settings = Wire.field(1, Data(0..<32)) + Wire.field(2, wrapped) + Wire.integer(3, ttl)
        let hot = Wire.field(138536474, Wire.field(146311580, settings))
        let group = base64 ? Wire.field(3, Data(hot.base64EncodedString().utf8)) : Wire.field(7, hot)
        return Wire.field(1, Wire.field(16, group))
    }
    private func request(_ wrapped: Data) -> Data { Wire.field(3, Wire.field(5, wrapped)) }

    func testKeysAreClientBoundAndExpire() {
        let vault = OnesieKeyVault(), now = Date(timeIntervalSince1970: 1000)
        let wrapped = Data(repeating: 9, count: 32)
        XCTAssertTrue(vault.capture(config(wrapped), client: "a", now: now))
        XCTAssertEqual(vault.keyForRequest(request(wrapped), client: "a", now: now), Data(0..<32))
        XCTAssertNil(vault.keyForRequest(request(wrapped), client: "b", now: now))
        XCTAssertNil(vault.keyForRequest(request(wrapped), client: "a", now: now.addingTimeInterval(5)))
        XCTAssertFalse(vault.ready(client: "a", now: now.addingTimeInterval(5)))
        XCTAssertEqual(vault.entryCount, 0)
    }

    func testBase64CapacityTTLClampAndClear() {
        let vault = OnesieKeyVault(), now = Date(timeIntervalSince1970: 1000)
        for i in 0..<40 {
            XCTAssertTrue(vault.capture(config(Data(repeating: UInt8(i), count: 16), ttl: .max, base64: true), client: "a", now: now))
        }
        XCTAssertEqual(vault.entryCount, 32)
        XCTAssertNil(vault.keyForRequest(request(Data(repeating: 0, count: 16)), client: "a", now: now))
        XCTAssertFalse(vault.ready(client: "a", now: now.addingTimeInterval(3600)))
        XCTAssertFalse(vault.capture(Data([0xff]), client: "a", now: now))
        vault.clear(); XCTAssertEqual(vault.entryCount, 0)
    }

    func testHostAndPathBoundaries() {
        XCTAssertTrue(ResponseProcessor.isAPIHost("YOUTUBEI.GOOGLEAPIS.COM"))
        XCTAssertFalse(ResponseProcessor.isAPIHost("youtubei.googleapis.com.attacker.test"))
        XCTAssertTrue(ResponseProcessor.isMediaHost("rr1.googlevideo.com"))
        XCTAssertFalse(ResponseProcessor.isMediaHost("evilgooglevideo.com"))
        XCTAssertFalse(ResponseProcessor.isMediaHost("googlevideo.com.attacker.test"))
        let processor = ResponseProcessor(enabled: true)
        let body = Wire.field(2, Data()) + Wire.field(11, Wire.field(1, Data("demoVideo01".utf8))) + Wire.field(68, Data())
        XCTAssertEqual(processor.processAPI(body, host: "other.test", path: "/youtubei/v1/player", client: "a").data, body)
        XCTAssertTrue(processor.processAPI(body, host: "youtubei.googleapis.com", path: "/youtubei/v1/player", client: "a").modified)
        XCTAssertTrue(processor.needsFreshConfiguration(host: "youtubei.googleapis.com", path: "/youtubei/v1/log_event", client: "a"))
        XCTAssertFalse(processor.needsFreshConfiguration(host: "other.test", path: "/youtubei/v1/log_event", client: "a"))
        XCTAssertNil(processor.makeStream(host: "rr1.googlevideo.com", path: "/videoplayback", contentType: "application/vnd.yt-ump", requestBody: Data(), client: "a"))
        XCTAssertNil(processor.makeStream(host: "rr1.googlevideo.com", path: "/initplayback", contentType: "application/vnd.yt-ump", contentEncoding: "gzip", requestBody: Data(), client: "a"))
        XCTAssertNotNil(processor.makeStream(host: "rr1.googlevideo.com", path: "/initplayback", contentType: "application/vnd.yt-ump; x=1", requestBody: Data(), client: "a"))
    }
}
