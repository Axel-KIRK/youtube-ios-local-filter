import Foundation
import Combine
import NetworkExtension

@MainActor
final class ConnectionController: ObservableObject {
    @Published private(set) var connectionStatus: NEVPNStatus = .invalid
    @Published private(set) var snapshot: TunnelStatus?
    @Published private(set) var busy = false
    @Published var message: String?
    private var manager: NETunnelProviderManager?
    private var refreshing = false
    private let providerID = "com.axelkirk.localfilter.Tunnel"

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
        defer { busy = false }
        do {
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
            await refresh()
        } catch {
            message = "The local connection could not start. Check that this build is signed for Network Extension and try again."
            await refresh()
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
        snapshot = nil
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
