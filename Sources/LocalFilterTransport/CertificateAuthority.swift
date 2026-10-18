import Foundation
import CryptoKit
import X509
import NIOSSL

/// A local authority; call on the proxy's serial event loop. Private material is never logged.
public final class CertificateAuthority {
    private let certificate: Certificate
    private let key: Certificate.PrivateKey
    private let algorithm: Certificate.SignatureAlgorithm
    private var contexts = [String: NIOSSLContext]()

    public init(certificatePEM: String, privateKeyPEM: String) throws {
        certificate = try Certificate(pemEncoded: certificatePEM)
        // mitmproxy stores the RSA key and certificate in one PEM file.
        let labels = ["PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY"]
        let blocks = labels.compactMap { label -> String? in
            guard let begin = privateKeyPEM.range(of: "-----BEGIN \(label)-----"),
                  let end = privateKeyPEM.range(of: "-----END \(label)-----", range: begin.upperBound..<privateKeyPEM.endIndex) else { return nil }
            return String(privateKeyPEM[begin.lowerBound..<end.upperBound])
        }
        guard blocks.count == 1 else { throw TransportError.invalidAuthority }
        key = try Certificate.PrivateKey(pemEncoded: blocks[0])
        guard key.publicKey == certificate.publicKey,
              case .isCertificateAuthority = try certificate.extensions.basicConstraints,
              certificate.notValidAfter > Date() else { throw TransportError.invalidAuthority }
        // Importing an existing RSA authority lets the Mac test reuse the trusted PoC certificate.
        let probe = Data("LocalFilter signing algorithm check".utf8)
        if (try? key.sign(bytes: probe, signatureAlgorithm: .ecdsaWithSHA256)) != nil {
            algorithm = .ecdsaWithSHA256
        } else if (try? key.sign(bytes: probe, signatureAlgorithm: .sha256WithRSAEncryption)) != nil {
            algorithm = .sha256WithRSAEncryption
        } else { throw TransportError.invalidAuthority }
    }

    public static func generate() throws -> (certificatePEM: String, privateKeyPEM: String) {
        let raw = P256.Signing.PrivateKey()
        let key = Certificate.PrivateKey(raw)
        let name = try DistinguishedName { CommonName("LocalFilter Personal CA") }
        let certificate = try Certificate(
            version: .v3, serialNumber: .init(), publicKey: key.publicKey,
            notValidBefore: Date().addingTimeInterval(-300),
            notValidAfter: Date().addingTimeInterval(365 * 86400),
            issuer: name, subject: name, signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                Critical(KeyUsage(keyCertSign: true, cRLSign: true))
            }, issuerPrivateKey: key)
        return (try certificate.serializeAsPEM().pemString, raw.pemRepresentation)
    }

    /// Public certificate only, suitable for the explicit iOS installation step.
    public func certificateDER() throws -> Data {
        let bytes = try NIOSSLCertificate.fromPEMBytes(Array(certificate.serializeAsPEM().pemString.utf8))
        return Data(try bytes[0].toDERBytes())
    }

    func serverContext(host: String) throws -> NIOSSLContext {
        guard DestinationPolicy.isTarget(host) else { throw TransportError.destinationDenied }
        if let cached = contexts[host] { return cached }
        let raw = P256.Signing.PrivateKey()
        let leaf = try Certificate(
            version: .v3, serialNumber: .init(), publicKey: Certificate.PrivateKey(raw).publicKey,
            notValidBefore: Date().addingTimeInterval(-300),
            notValidAfter: min(certificate.notValidAfter, Date().addingTimeInterval(7 * 86400)),
            issuer: certificate.subject, subject: try DistinguishedName { CommonName(host) },
            signatureAlgorithm: algorithm,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames([.dnsName(host)])
            }, issuerPrivateKey: key)
        let chain = try NIOSSLCertificate.fromPEMBytes(Array(leaf.serializeAsPEM().pemString.utf8))
        var config = TLSConfiguration.makeServerConfiguration(
            certificateChain: chain.map { .certificate($0) },
            privateKey: .privateKey(try NIOSSLPrivateKey(bytes: Array(raw.pemRepresentation.utf8), format: .pem)))
        config.applicationProtocols = ["http/1.1"]
        config.minimumTLSVersion = .tlsv12
        let context = try NIOSSLContext(configuration: config)
        if contexts.count >= 32 { contexts.removeAll(keepingCapacity: true) }
        contexts[host] = context
        return context
    }
}

enum TransportError: Error {
    case invalidAuthority, destinationDenied, invalidRequest, oversized, upstreamClosed
}
