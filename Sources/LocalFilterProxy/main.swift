import Foundation
import LocalFilterTransport

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty || arguments.contains("--help") {
        print("""
        local-filter-proxy --ca-cert PATH --ca-key PATH [--port 8881] [--observe]
                           [--listen IP --allow-client IP ...]
        local-filter-proxy --create-ca PRIVATE_DIRECTORY

        Experimental YouTube-only HTTPS CONNECT backend. Defaults to loopback.
        Other destinations are rejected. It is not a standalone iOS VPN.
        Certificate keys and request payloads are never logged.
        """)
        exit(0)
    }
    if arguments.count == 2, arguments[0] == "--create-ca" {
        let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw CLIError("The certificate directory already exists; refusing to overwrite it.")
        }
        let pair = try CertificateAuthority.generate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        for (name, text) in [("ca.pem", pair.certificatePEM), ("ca-key.pem", pair.privateKeyPEM)] {
            let path = directory.appendingPathComponent(name).path
            guard FileManager.default.createFile(atPath: path, contents: Data(text.utf8),
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw CLIError("Could not write certificate material.")
            }
        }
        print("Created a private local authority. Install only ca.pem on the test device.")
        exit(0)
    }
    var configuration = ProxyConfiguration(), cert: String?, key: String?, index = 0
    while index < arguments.count {
        let flag = arguments[index]; index += 1
        if flag == "--observe" { configuration.enabled = false; continue }
        guard index < arguments.count else { throw CLIError("Missing option value.") }
        let value = arguments[index]; index += 1
        switch flag {
        case "--ca-cert": cert = value
        case "--ca-key": key = value
        case "--listen": configuration.host = value
        case "--allow-client": configuration.allowedClients.insert(value)
        case "--port":
            guard let port = Int(value), (1024...65535).contains(port) else { throw CLIError("Invalid port.") }
            configuration.port = port
        default: throw CLIError("Unknown option. Use --help.")
        }
    }
    guard let cert, let key else { throw CLIError("Both --ca-cert and --ca-key are required.") }
    let authority = try CertificateAuthority(certificatePEM: String(contentsOfFile: cert, encoding: .utf8),
                                            privateKeyPEM: String(contentsOfFile: key, encoding: .utf8))
    let server = try ProxyServer(configuration: configuration, authority: authority) { message in
        print("\(ISO8601DateFormatter().string(from: Date())) \(message)")
        fflush(stdout)
    }
    let port = try server.start()
    print("LocalFilter listening on \(configuration.host):\(port); rewriting=\(configuration.enabled)")
    fflush(stdout)
    try server.waitUntilClosed()
    try server.stop()
} catch {
    // Avoid printing underlying TLS or request errors that could contain private values.
    fputs("LocalFilter could not start. Check arguments, certificate/key pairing, and the listening port.\n", stderr)
    if let error = error as? CLIError { fputs(error.message + "\n", stderr) }
    exit(1)
}

struct CLIError: Error { let message: String; init(_ message: String) { self.message = message } }
