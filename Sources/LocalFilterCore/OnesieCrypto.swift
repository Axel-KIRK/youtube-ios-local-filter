import Foundation
import CryptoKit
import CommonCrypto
import Security
import CLocalCompression

enum OnesieCrypto {
    static func crypt(_ input: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 32, iv.count == 16 else { throw DecodeError.crypto }
        var context: CCCryptorRef?
        let status = iv.withUnsafeBytes { vector in
            key.withUnsafeBytes { material in
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), vector.baseAddress,
                    material.baseAddress, 16, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &context)
            }
        }
        guard status == kCCSuccess, let context else { throw DecodeError.crypto }
        defer { CCCryptorRelease(context) }
        var output = Data(count: input.count + 16), written = 0
        let capacity = output.count
        let update = output.withUnsafeMutableBytes { target in
            input.withUnsafeBytes { source in
                CCCryptorUpdate(context, source.baseAddress, input.count,
                                target.baseAddress, capacity, &written)
            }
        }
        guard update == kCCSuccess, written == input.count else { throw DecodeError.crypto }
        output.count = written
        return output
    }

    static func tag(_ cipher: Data, iv: Data, key: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: cipher + iv,
             using: SymmetricKey(data: key.suffix(16))))
    }

    static func authenticated(_ cipher: Data, iv: Data, tag: Data, key: Data) -> Bool {
        guard key.count == 32, iv.count == 16, tag.count == 32 else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: cipher + iv,
                   using: SymmetricKey(data: key.suffix(16)))
    }

    static func randomIV() throws -> Data {
        var bytes = Data(count: 16)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw DecodeError.crypto }
        return bytes
    }

    static func gzip(_ input: Data, compress: Bool, limit: Int = Wire.limit) throws -> Data {
        guard input.count <= limit, limit >= 0, limit < Int(UInt32.max) else {
            throw DecodeError.oversized
        }
        var output = Data(count: limit + 1), written = limit + 1
        let status = output.withUnsafeMutableBytes { target in
            input.withUnsafeBytes { source in
                let function = compress ? lf_gzip : lf_gunzip
                return function(source.bindMemory(to: UInt8.self).baseAddress, input.count,
                                target.bindMemory(to: UInt8.self).baseAddress, &written)
            }
        }
        guard status == 0, written <= limit else { throw DecodeError.compression }
        output.count = written; return output
    }

    static func decode(_ data: Data, compression: UInt64) throws -> Data {
        switch compression {
        case 0: return data
        case 1: return try gzip(data, compress: false)
        default: throw DecodeError.compression
        }
    }

    static func encode(_ data: Data, compression: UInt64) throws -> Data {
        switch compression {
        case 0: return data
        case 1: return try gzip(data, compress: true)
        default: throw DecodeError.compression
        }
    }
}
