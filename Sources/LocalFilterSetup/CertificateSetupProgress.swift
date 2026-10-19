import Foundation

/// Remembers where setup can resume, never whether iOS installed or trusts a CA.
public struct CertificateSetupProgress: Codable, Equatable {
    public private(set) var certificateID: String?
    public private(set) var downloadOpenedAt: Date?
    public private(set) var certificateServedAt: Date?
    public private(set) var legacyContinuationAt: Date?

    public init() {}

    public var canContinue: Bool { legacyContinuationAt != nil || certificateServedAt != nil }

    /// A different CA invalidates all progress. A missing receipt does not: the
    /// user may have installed the profile, or the extension may have restarted.
    public mutating func observe(certificateID: String, servedAt: Date?, legacyOpenedAt: Date? = nil) {
        guard !certificateID.isEmpty else { return }
        if self.certificateID != certificateID {
            let firstObservation = self.certificateID == nil
            self = Self()
            self.certificateID = certificateID
            // Old builds only recorded opening Safari. Preserve the continuation
            // affordance without presenting this as a confirmed transfer.
            if firstObservation { legacyContinuationAt = legacyOpenedAt }
        }
        if let servedAt, servedAt > (certificateServedAt ?? .distantPast) {
            certificateServedAt = servedAt
        }
    }

    public mutating func recordDownloadOpened(at date: Date = Date()) {
        downloadOpenedAt = date
    }
}
