import Foundation
import Network

/// Checks the device's real TLS trust through the local proxy before system traffic is redirected.
/// No custom trust anchors, authentication, cookies, redirects, or direct-connection fallback.
@available(iOS 17.0, macOS 14.0, *)
public enum ConnectionPreflight {
    public enum Failure: Error, Equatable {
        case certificateNotTrusted
        case connectionUnavailable
    }

    public static func verify(port: UInt16) async throws {
        guard port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw Failure.connectionUnavailable
        }
        var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: endpointPort))
        proxy.allowFailover = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.proxyConfigurations = [proxy]
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://youtubei.googleapis.com/youtubei/v1/player")!)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            // This endpoint normally returns 405 to HEAD. Any ordinary HTTP response establishes
            // the TLS path; reject proxy/upstream failures and redirects rather than following them.
            guard let response = response as? HTTPURLResponse,
                  (200..<500).contains(response.statusCode),
                  !(300..<400).contains(response.statusCode), response.statusCode != 407 else {
                throw Failure.connectionUnavailable
            }
        } catch let error as URLError {
            switch error.code {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .secureConnectionFailed:
                throw Failure.certificateNotTrusted
            default: throw Failure.connectionUnavailable
            }
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
