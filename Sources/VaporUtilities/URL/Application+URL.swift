import Vapor
import Foundation

extension Application {
    /// Constructs a URL using the application's configured host and scheme.
    ///
    /// When `app.url.baseURL` is configured, that value is used as the base.
    /// Otherwise the scheme is determined from the server's TLS configuration
    /// and the host is read from the server configuration.
    ///
    /// ```swift
    /// let url = app.url(for: "/health", query: ["token": "abc"])
    /// // "https://example.com/health?token=abc"
    /// ```
    ///
    /// - Parameters:
    ///   - path: The path component (e.g. `"/health"`).
    ///   - query: Optional query parameters to append.
    /// - Returns: An absolute URL, or `nil` if the configuration is incomplete.
    public func url(for path: String, query: [String: String] = [:]) -> URL? {
        if let baseURL = self.url.baseURL {
            return Self._buildURL(base: baseURL, path: path, query: query)
        }

        let scheme = self.http.server.configuration.tlsConfiguration != nil ? "https" : "http"
        let host = self.http.server.configuration.hostname

        guard var components = URLComponents(string: "\(scheme)://\(host)") else {
            return nil
        }

        components.path = path.hasPrefix("/") ? path : "/\(path)"

        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        return components.url
    }

    /// Build a URL from a base URL, path, and query parameters.
    private static func _buildURL(base: URL, path: String, query: [String: String]) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: true) else { return nil }
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }
}