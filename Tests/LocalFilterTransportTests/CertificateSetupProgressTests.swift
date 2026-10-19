import XCTest
import LocalFilterSetup

final class CertificateSetupProgressTests: XCTestCase {
    func testOpeningSafariAloneDoesNotConfirmDelivery() {
        var progress = CertificateSetupProgress()
        progress.observe(certificateID: "ca", servedAt: nil)
        progress.recordDownloadOpened()
        XCTAssertFalse(progress.canContinue)
        XCTAssertNil(progress.certificateServedAt)
    }
    func testReceiptSurvivesRelaunchAndMissingExtensionReceipt() throws {
        var progress = CertificateSetupProgress()
        let sent = Date(timeIntervalSince1970: 100)
        progress.observe(certificateID: "first-ca", servedAt: sent)
        progress = try JSONDecoder().decode(CertificateSetupProgress.self, from: JSONEncoder().encode(progress))
        progress.observe(certificateID: "first-ca", servedAt: nil)
        XCTAssertTrue(progress.canContinue)
        XCTAssertEqual(progress.certificateServedAt, sent)
    }

    func testReplacingTheCertificateInvalidatesOldProgress() {
        var progress = CertificateSetupProgress()
        progress.observe(certificateID: "old-ca", servedAt: Date())
        progress.recordDownloadOpened()
        progress.observe(certificateID: "new-ca", servedAt: nil, legacyOpenedAt: Date())
        XCTAssertFalse(progress.canContinue)
        XCTAssertNil(progress.certificateServedAt)
    }

    func testOldSafariOpenResumesWithoutClaimingDelivery() {
        var progress = CertificateSetupProgress()
        progress.observe(certificateID: "same-ca", servedAt: nil,
                         legacyOpenedAt: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(progress.canContinue)
        XCTAssertNil(progress.certificateServedAt)
    }
}
