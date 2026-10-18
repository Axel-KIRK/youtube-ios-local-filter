import Foundation
import Security
import LocalFilterTransport

/// The extension alone owns the private key. No shared files, sync, or key export.
enum AuthorityStore {
    private struct Material: Codable {
        let certificatePEM: String
        let privateKeyPEM: String
    }

    static func loadOrCreate() throws -> CertificateAuthority {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.axelkirk.localfilter.authority",
            kSecAttrAccount as String: "installation-v1",
            kSecAttrSynchronizable as String: false
        ]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &found)
        if status == errSecSuccess, let data = found as? Data {
            let stored = try JSONDecoder().decode(Material.self, from: data)
            return try CertificateAuthority(certificatePEM: stored.certificatePEM, privateKeyPEM: stored.privateKeyPEM)
        }
        // Locked, unavailable, or corrupt storage must never silently replace a trusted authority.
        guard status == errSecItemNotFound else { throw StoreError.unavailable }
        let generated = try CertificateAuthority.generate()
        let stored = Material(certificatePEM: generated.certificatePEM, privateKeyPEM: generated.privateKeyPEM)
        let authority = try CertificateAuthority(certificatePEM: stored.certificatePEM, privateKeyPEM: stored.privateKeyPEM)
        var item = query
        item[kSecValueData as String] = try JSONEncoder().encode(stored)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw StoreError.unavailable }
        return authority
    }

    private enum StoreError: Error { case unavailable }
}
