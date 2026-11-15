import Foundation
import HTTPTypes
import Vapor

extension Request {
    /// The `Host` field name.
    ///
    /// `HTTPField.Name.host` is unavailable in swift-http-types, so the
    /// canonical name is constructed directly.
    private static let hostFieldName = HTTPField.Name("Host")!

    /// The absolute URL of the current request.
    ///
    /// The origin is resolved from the `Forwarded` header (or its
    /// `X-Forwarded-*` equivalents), then the `Host` header, then the local
    /// address. Pass `baseURL` to override the detected origin, which is
    /// useful for direct TLS deployments where no proxy supplies the scheme.
    ///
    /// ```swift
    /// // GET https://example.com/users?page=1
    /// print(request.absoluteURL()) // "https://example.com/users?page=1"
    /// ```
    ///
    /// - Parameter baseURL: An optional origin override.
    /// - Returns: The absolute URL of the request.
    public func absoluteURL(baseURL: URL? = nil) -> URL {
        // Use the configured base URL when provided.
        if let baseURL {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
            components?.path = self.url.path.isEmpty ? "/" : self.url.path
            components?.query = self.url.query
            return components?.url ?? baseURL
        }

        // Prefer the forwarded origin, then the Host header, then the local address.
        let forwarded = self.headers.forwarded.first
        let scheme = forwarded?.proto ?? "http"

        let host: String
        let port: Int?
        if let authority = forwarded?.host ?? self.headers[Self.hostFieldName] {
            (host, port) = Self.splitHostPort(authority)
        } else {
            host = self.localAddress?.host ?? "localhost"
            port = self.localAddress?.port
        }

        // Build the origin + path, keeping the request's query.
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = self.url.path.isEmpty ? "/" : self.url.path
        components.query = self.url.query
        return components.url ?? URL(string: "/")!
    }

    /// Constructs a URL relative to the current request's base.
    ///
    /// The returned URL uses the request's origin, with the given path and
    /// optional query parameters. Pass `baseURL` to override the detected
    /// origin.
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
    ///   - baseURL: An optional origin override.
    /// - Returns: An absolute URL, or `nil` if the path is invalid.
    public func url(for path: String, query: [String: String] = [:], baseURL: URL? = nil) -> URL? {
        let origin = self.absoluteURL(baseURL: baseURL)
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: true) else {
            return nil
        }

        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = query.isEmpty
            ? nil
            : query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url
    }

    /// Splits an authority into its host and optional port.
    ///
    /// - Parameter value: The authority, e.g. `example.com:8080` or `[::1]:8080`.
    /// - Returns: The host and port, with `nil` when no port is present.
    private static func splitHostPort(_ value: String) -> (host: String, port: Int?) {
        // IPv6 literals are bracketed, e.g. "[::1]:8080".
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return (value, nil) }
            let host = String(value[value.index(after: value.startIndex)..<close])
            let rest = value[value.index(after: close)...]
            let port = rest.hasPrefix(":") ? Int(rest.dropFirst()) : nil
            return (host, port)
        }

        // Otherwise split on the last colon.
        guard let colon = value.lastIndex(of: ":") else { return (value, nil) }
        let host = String(value[..<colon])
        let port = Int(value[value.index(after: colon)...])
        return (host, port)
    }
}
