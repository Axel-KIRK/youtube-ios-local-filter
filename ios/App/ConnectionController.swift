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
    @Published var message: String?
    private var manager: NETunnelProviderManager?
    private var refreshing = false
    private let providerID = "com.axelkirk.localfilter.Tunnel"
    private let diagnostics = Logger(subsystem: "com.axelkirk.localfilter", category: "setup")

    var running: Bool { [.connected, .connecting, .reasserting, .disconnecting].contains(connectionStatus) }

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
        busy = true; message = nil
        defer { busy = false; checkingCertificate = false }
        do {
            certificateVerified = false
            // Setup has no system proxy settings. Missing trust must never redirect YouTube.
            try await connect(.setup)
            try await waitForStatus(.setup)
            if mode == .filter {
                checkingCertificate = true
                try await verifyCurrentCertificate()
                certificateVerified = true
                checkingCertificate = false
                // Restart resets setup/probe counters before actual YouTube traffic is counted.
                try await connect(.filter)
                try await waitForStatus(.filter)
            }
        } catch let error as ConnectionPreflight.Failure {
            showPreflightFailure(error)
            await refresh()
        } catch {
            manager?.connection.stopVPNTunnel()
            certificateVerified = false
            message = "The local connection could not start. Try preparing the connection again."
            await refresh()
        }
    }

    /// Recheck on return from Settings. No stored checkbox is treated as evidence of trust.
    func checkCertificate() async {
        guard !busy, snapshot?.mode == .setup else { return }
        busy = true; checkingCertificate = true; message = nil
        defer { busy = false; checkingCertificate = false }
        do {
            try await verifyCurrentCertificate()
            certificateVerified = true
        } catch let error as ConnectionPreflight.Failure { showPreflightFailure(error) }
        catch { showPreflightFailure(.connectionUnavailable) }
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
            diagnostics.error("Certificate preflight failed: certificate_not_trusted; filtering remains off")
            message = "The certificate check failed. Install LocalFilter Personal CA in Settings, then enable its full trust under General → About → Certificate Trust Settings. Filtering is still off."
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
        manager?.connection.stopVPNTunnel()
        snapshot = nil
        certificateVerified = false
        connectionStatus = manager?.connection.status ?? .invalid
    }

    func removeConfiguration() async {
        guard !running, !busy else { return }
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
