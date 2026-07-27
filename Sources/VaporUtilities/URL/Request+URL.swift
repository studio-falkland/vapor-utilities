import Vapor
import Foundation

extension Request {
    /// The absolute URL of the current request, constructed from the scheme,
    /// host, and path.
    ///
    /// The scheme is determined from the server's TLS configuration. The host
    /// is read from the `Host` header. When `app.url.baseURL` is configured,
    /// it takes precedence over automatic detection.
    ///
    /// ```swift
    /// // GET https://example.com/users?page=1
    /// print(request.absoluteURL) // "https://example.com/users?page=1"
    /// ```
    public var absoluteURL: URL {
        let scheme = self.application.http.server.configuration.tlsConfiguration != nil ? "https" : "http"

        let host = self.headers.first(name: "Host")
            ?? self.application.http.server.configuration.hostname

        let fullHost = host.contains(":") ? host
            : self.port.map { "\(host):\($0)" } ?? host

        guard var components = URLComponents(string: "\(scheme)://\(fullHost)") else {
            return URL(string: "/")!
        }

        components.path = self.url.path.isEmpty ? "/" : self.url.path
        components.query = self.url.query

        return components.url ?? URL(string: "/")!
    }

    /// Constructs a URL relative to the current request's base.
    ///
    /// The returned URL uses the request's scheme and host, with the given
    /// path and optional query parameters. When `app.url.baseURL` is
    /// configured, it takes precedence over automatic detection.
    ///
    /// ```swift
    /// // GET https://example.com/users
    /// let url = request.url(for: "/login", query: ["redirect": "/profile"])
    /// // "https://example.com/login?redirect=%2Fprofile"
    /// ```
    ///
    /// - Parameters:
    ///   - path: The path component (e.g. `"/login"`).
    ///   - query: Optional query parameters to append.
    /// - Returns: An absolute URL, or `nil` if the path is invalid.
    public func url(for path: String, query: [String: String] = [:]) -> URL? {
        if let baseURL = self.application.url.baseURL {
            return Self._buildURL(base: baseURL, path: path, query: query)
        }

        let scheme = self.application.http.server.configuration.tlsConfiguration != nil ? "https" : "http"

        let host = self.headers.first(name: "Host")
            ?? self.application.http.server.configuration.hostname

        let fullHost = host.contains(":") ? host
            : (self.port.map { "\(host):\($0)" } ?? host)

        guard var components = URLComponents(string: "\(scheme)://\(fullHost)") else {
            return nil
        }

        components.path = path.hasPrefix("/") ? path : "/\(path)"

        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        return components.url
    }

    /// The port the request was received on, determined from the `Host` header.
    private var port: Int? {
        guard let hostHeader = self.headers.first(name: "Host"),
              let colonIndex = hostHeader.lastIndex(of: ":") else {
            return nil
        }
        return Int(hostHeader[hostHeader.index(after: colonIndex)...])
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