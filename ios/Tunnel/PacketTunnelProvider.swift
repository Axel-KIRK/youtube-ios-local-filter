import Foundation
import NetworkExtension
import LocalFilterTransport
import OSLog

/// Experimental proxy-only settings. No default IP route or packet discard loop.
/// A successful start is not evidence that YouTube honors the proxy on this device.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let worker = DispatchQueue(label: "LocalFilter.tunnel.lifecycle")
    private let stateLock = NSLock()
    private var proxy: ProxyServer?
    private var snapshot: TunnelStatus?
    private var pendingStart: ((Error?) -> Void)?
    private var startToken: UUID?
    private let diagnostics = Logger(subsystem: "com.axelkirk.localfilter", category: "transport")
    private var lastDiagnosticReport: String?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let mode = (options?["mode"] as? String).flatMap(ConnectionMode.init(rawValue:)) ?? .setup
        let token = UUID()
        worker.async {
            do {
                guard self.proxy == nil, self.pendingStart == nil else {
                    completionHandler(StartError.alreadyRunning)
                    return
                }
                self.pendingStart = completionHandler
                self.startToken = token
                let authority = try AuthorityStore.loadOrCreate()
                var configuration = ProxyConfiguration()
                configuration.port = 0
                configuration.maximumConnections = 8
                configuration.servesCertificate = true
                let proxy = try ProxyServer(configuration: configuration, authority: authority) { [weak self] event in
                    guard let self else { return }
                    self.stateLock.lock()
                    self.snapshot?.record(event)
                    let failure = self.snapshot?.lastFailure
                    self.stateLock.unlock()
                    if (event.contains("_failed ") || event.contains("_rejected ")), let failure {
                        self.diagnostics.error("Transport failure: \(failure, privacy: .public)")
                    }
                }
                self.proxy = proxy
                let port = try proxy.start()
                self.stateLock.lock()
                self.snapshot = TunnelStatus(mode: mode, certificateURL: "http://127.0.0.1:\(port)/certificate.cer")
                self.stateLock.unlock()

                let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
                let ipv4 = NEIPv4Settings(addresses: ["192.0.2.1"], subnetMasks: ["255.255.255.255"])
                ipv4.includedRoutes = []
                ipv4.excludedRoutes = []
                settings.ipv4Settings = ipv4
                // Setup serves only the public certificate, without diverting YouTube traffic.
                if mode == .filter {
                    let http = NEProxySettings()
                    http.httpEnabled = false
                    http.httpsEnabled = true
                    http.httpsServer = NEProxyServer(address: "127.0.0.1", port: port)
                    http.matchDomains = ["youtubei.googleapis.com", "youtubei-att.googleapis.com", "googlevideo.com"]
                    http.excludeSimpleHostnames = true
                    settings.proxySettings = http
                }
                self.setTunnelNetworkSettings(settings) { error in
                    self.worker.async {
                        guard self.startToken == token, let pending = self.pendingStart else { return }
                        self.pendingStart = nil
                        self.startToken = nil
                        if let error {
                            self.shutdown()
                            pending(error)
                        } else { pending(nil) }
                    }
                }
            } catch {
                self.pendingStart = nil
                self.startToken = nil
                self.shutdown()
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        worker.async {
            let pending = self.pendingStart
            self.pendingStart = nil
            self.startToken = nil
            self.shutdown()
            pending?(StartError.cancelled)
            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard messageData == Data("status".utf8) else { completionHandler?(nil); return }
        stateLock.lock()
        let status = snapshot
        let report = status.map {
            "mode=\($0.mode.rawValue) connections=\($0.connections) tunnels=\($0.connectRequests) requests=\($0.decryptedRequests) responses=\($0.responses) rewritten=\($0.rewrittenResponses) upstreamFailures=\($0.upstreamFailures) downstreamFailures=\($0.downstreamFailures) rejections=\($0.rejections)"
        }
        let changed = report != lastDiagnosticReport
        lastDiagnosticReport = report
        stateLock.unlock()
        if changed, let report { diagnostics.info("Transport status: \(report, privacy: .public)") }
        completionHandler?(status.flatMap { try? JSONEncoder().encode($0) })
    }

    private func shutdown() {
        try? proxy?.stop()
        proxy = nil
        stateLock.lock(); snapshot = nil; stateLock.unlock()
    }

    private enum StartError: Error { case alreadyRunning, cancelled }
}
