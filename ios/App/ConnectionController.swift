import Foundation
import Combine
import NetworkExtension
import LocalFilterSetup
import OSLog

@MainActor
final class ConnectionController: ObservableObject {
    @Published private(set) var connectionStatus: NEVPNStatus = .invalid
    @Published private(set) var snapshot: TunnelStatus?
    @Published private(set) var busy = false
    @Published private(set) var checkingCertificate = false
    @Published private(set) var certificateVerified = false
    @Published private(set) var certificateRequired = false
    @Published private(set) var hasCompletedSetup = UserDefaults.standard.bool(forKey: "hasCompletedSetup")
    // This is an activation request, never evidence that a certificate is trusted.
    @Published private(set) var enableWhenReady = UserDefaults.standard.bool(forKey: "enableWhenReady") {
        didSet { UserDefaults.standard.set(enableWhenReady, forKey: "enableWhenReady") }
    }
    @Published var message: String?
    private var manager: NETunnelProviderManager?
    private var refreshing = false
    private let providerID = "com.axelkirk.localfilter.Tunnel"
    private let diagnostics = Logger(subsystem: "com.axelkirk.localfilter", category: "setup")

    var running: Bool { [.connected, .connecting, .reasserting, .disconnecting].contains(connectionStatus) }
    var filtering: Bool { connectionStatus == .connected && snapshot?.mode == .filter }
    var certificateURL: URL? {
        guard let text = snapshot?.certificateURL, let url = URL(string: text),
              url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
              url.path == "/certificate.cer" else { return nil }
        return url
    }

    /// Continue only a setup the user requested. Stop cancels this persisted intent.
    func resumeSetup() async {
        await refresh()
        guard enableWhenReady else {
            diagnostics.info("No setup request to resume")
            return
        }
        guard !busy else { return }
        await start(.filter)
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            if manager == nil {
                let loaded = try await NETunnelProviderManager.loadAllFromPreferences().first {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID
                }
                if manager == nil { manager = loaded }
            }
            connectionStatus = manager?.connection.status ?? .invalid
            guard connectionStatus == .connected, let session = manager?.connection as? NETunnelProviderSession else {
                snapshot = nil; return
            }
            // A provider that is suspended or terminating may never reply. Never leave the UI waiting.
            let reply = ProviderReply()
            snapshot = try await withCheckedThrowingContinuation { continuation in
                reply.continuation = continuation
                do {
                    try session.sendProviderMessage(Data("status".utf8)) { data in
                        let status = data.flatMap { try? JSONDecoder().decode(TunnelStatus.self, from: $0) }
                        reply.complete(.success(status))
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reply.complete(.success(nil)) }
                } catch { reply.complete(.failure(error)) }
            }
        } catch { message = "Connection status is unavailable. Try again in a moment." }
    }

    func start(_ mode: ConnectionMode) async {
        guard !busy else { return }
        if mode == .filter { enableWhenReady = true }
        busy = true; message = nil
        defer { busy = false; checkingCertificate = false }
        do {
            if mode == .filter, filtering {
                enableWhenReady = false
                return
            }
            certificateVerified = false
            certificateRequired = false
            // Setup has no system proxy settings. Missing trust must never redirect YouTube.
            // Reuse setup on return from Settings so its certificate download URL stays valid.
            if connectionStatus != .connected || snapshot?.mode != .setup {
                try await connect(.setup)
                try await waitForStatus(.setup)
            }
            if mode == .filter {
                checkingCertificate = true
                try await verifyCurrentCertificate()
                certificateVerified = true
                checkingCertificate = false
                // Restart resets setup/probe counters before actual YouTube traffic is counted.
                try await connect(.filter)
                try await waitForStatus(.filter)
                enableWhenReady = false
                hasCompletedSetup = true
                UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
                diagnostics.info("Guided setup complete; filtering enabled")
            }
        } catch let error as ConnectionPreflight.Failure {
            showPreflightFailure(error)
            await refresh()
        } catch {
            manager?.connection.stopVPNTunnel()
            certificateVerified = false
            message = "The local connection could not start. Tap Try again to continue setup."
            await refresh()
        }
    }

    private func verifyCurrentCertificate() async throws {
        guard let status = snapshot, status.mode == .setup,
              let url = URL(string: status.certificateURL), url.scheme == "http", url.host == "127.0.0.1",
              let port = url.port.flatMap(UInt16.init(exactly:)) else {
            throw ConnectionPreflight.Failure.connectionUnavailable
        }
        try await ConnectionPreflight.verify(port: port)
        diagnostics.info("Certificate preflight passed")
    }

    private func showPreflightFailure(_ failure: ConnectionPreflight.Failure) {
        certificateVerified = false
        switch failure {
        case .certificateNotTrusted:
            certificateRequired = true
            diagnostics.error("Certificate preflight failed: certificate_not_trusted; filtering remains off")
            // Expected during first setup: the view presents the installation guide, not an error wall.
            message = nil
        case .connectionUnavailable:
            diagnostics.error("Certificate preflight failed: connection_unavailable; filtering remains off")
            message = "The connection check could not reach YouTube through the local proxy. Check your internet connection and try again. Filtering is still off."
        }
    }

    private func waitForStatus(_ mode: ConnectionMode) async throws {
        for _ in 0..<30 {
            await refresh()
            if connectionStatus == .connected, snapshot?.mode == mode { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw ControllerError.unavailable
    }

    private func connect(_ mode: ConnectionMode) async throws {
        snapshot = nil
        if manager == nil {
            manager = try await NETunnelProviderManager.loadAllFromPreferences().first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID
            }
        }
        let manager = manager ?? NETunnelProviderManager()
        if ![.disconnected, .invalid].contains(manager.connection.status) {
            manager.connection.stopVPNTunnel()
            for _ in 0..<50 {
                if [.disconnected, .invalid].contains(manager.connection.status) { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard [.disconnected, .invalid].contains(manager.connection.status) else { throw ControllerError.busy }
        }
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = providerID
        configuration.serverAddress = "On this iPhone"
        configuration.disconnectOnSleep = false
        configuration.includeAllNetworks = false
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "LocalFilter"
        manager.isEnabled = true
        manager.isOnDemandEnabled = false
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        self.manager = manager
        guard let session = manager.connection as? NETunnelProviderSession else { throw ControllerError.unavailable }
        try session.startTunnel(options: ["mode": mode.rawValue as NSString])
    }

    func stop() {
        enableWhenReady = false
        manager?.connection.stopVPNTunnel()
        snapshot = nil
        certificateVerified = false
        certificateRequired = false
        message = nil
        connectionStatus = manager?.connection.status ?? .invalid
    }

    #if DEBUG
    /// Device diagnostics can exercise cancellation without a remote UI-tap service.
    func stopSavedConnection() async {
        enableWhenReady = false
        while refreshing { try? await Task.sleep(nanoseconds: 20_000_000) }
        await refresh()
        stop()
    }
    #endif

    func removeConfiguration() async {
        guard !running, !busy else { return }
        enableWhenReady = false
        busy = true
        defer { busy = false }
        do {
            try await manager?.removeFromPreferences()
            manager = nil; snapshot = nil; connectionStatus = .invalid
        } catch { message = "The connection could not be removed. You can remove LocalFilter in Settings → General → VPN & Device Management." }
    }

    private enum ControllerError: Error { case busy, unavailable }
}

private final class ProviderReply: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<TunnelStatus?, Error>?
    func complete(_ result: Result<TunnelStatus?, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
