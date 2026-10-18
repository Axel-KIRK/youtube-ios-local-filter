import XCTest
@testable import LocalFilterCore

final class RewriteTests: XCTestCase {
    let clean = Wire.field(2, Data()) + Wire.field(11, Wire.field(1, Data("demoVideo01".utf8)))
    var player: Data { clean + Wire.field(7, Data([1])) + Wire.field(45, Data([2])) + Wire.field(68, Data([3])) }

    func testOnlyKnownAdvertisingFieldsAreRemoved() {
        let unknown = Wire.field(778, Data([0, 1, 2])) + Wire.integer(7, 42)
        let result = AdProgramRewriter.rewriteAPI(player + unknown, path: "/youtubei/v1/player", enabled: true)
        XCTAssertEqual(result.data, clean + unknown)
        XCTAssertEqual(result.reports.first?.adFields, ["playerAds": 1, "adPlacements": 1, "adSlots": 1])
        XCTAssertTrue(result.modified)
    }

    func testGetWatchPreservesOtherFieldsAndRepeatedResponses() {
        let input = Wire.field(1, Wire.field(2, player) + Wire.field(3, Data([1]))) + Wire.field(1, Wire.field(2, player))
        let expected = Wire.field(1, Wire.field(2, clean) + Wire.field(3, Data([1]))) + Wire.field(1, Wire.field(2, clean))
        let result = AdProgramRewriter.rewriteAPI(input, path: "/youtubei/v1/get_watch", enabled: true)
        XCTAssertEqual(result.data, expected); XCTAssertEqual(result.reports.count, 2)
    }

    func testObserveAndUnknownPathsStayIdentical() {
        for (path, enabled) in [("/youtubei/v1/player", false), ("/unrelated/player", true)] {
            let result = AdProgramRewriter.rewriteAPI(player, path: path, enabled: enabled)
            XCTAssertEqual(result.data, player); XCTAssertFalse(result.modified)
        }
    }

    func testMalformedOrAmbiguousInputFallsBackAtomically() {
        let malformed = [player + Data([0xff]), Wire.field(68, Data([1])),
                         player + Wire.field(11, Wire.field(1, Data("otherVideo1".utf8))),
                         Wire.field(1, Wire.field(2, player)) + Wire.field(1, Data([0xff]))]
        for data in malformed {
            let result = AdProgramRewriter.rewriteAPI(data, path: data == malformed.last ? "/youtubei/v1/get_watch" : "/youtubei/v1/player", enabled: true)
            XCTAssertEqual(result.data, data); XCTAssertFalse(result.modified)
            XCTAssertFalse(result.reports.contains(where: \.removed))
        }
    }

    func testUnknownWireEncodingIsPreservedExactly() {
        // Field 100 varint 1 encoded non-canonically, followed by fixed32/fixed64.
        let unknown = Wire.varint(100 << 3) + Data([0x81, 0])
            + Wire.varint(101 << 3 | 5) + Data(repeating: 7, count: 4)
            + Wire.varint(102 << 3 | 1) + Data(repeating: 8, count: 8)
        let result = AdProgramRewriter.rewriteAPI(player + unknown, path: "/youtubei/v1/player", enabled: true)
        XCTAssertEqual(result.data, clean + unknown)
    }

    func testWireRejectsOverflowAndTruncation() {
        for bytes in [Data(repeating: 0xff, count: 11), Data([0]), Data([10, 20, 1]), Data([8] + Array(repeating: 0xff, count: 9) + [2])] {
            XCTAssertThrowsError(try Wire.parse(bytes))
        }
    }

    func testLocalDiagnosticExercisesActualEngine() {
        let result = LocalDiagnostic.run()
        XCTAssertTrue(result.passed); XCTAssertTrue(result.mediaUnchanged)
        XCTAssertEqual(result.removedFieldCount, 2)
    }
}
