import Vapor
import Foundation

/// Configuration for URL generation in a Vapor application.
///
/// Set `app.url.baseURL` to a full URL (scheme + host + optional port) to
/// override the automatic detection from server configuration. This is useful
/// for production deployments behind a reverse proxy where the server's
/// bind address differs from the public URL.
///
/// The `APP_URL` environment variable (from `.env` or the process environment)
/// is read automatically and used as the default value.
///
/// ```swift
/// app.url.baseURL = URL(string: "https://example.com")
/// ```
///
/// Or in `.env`:
/// ```env
/// APP_URL=https://example.com
/// ```
public struct URLConfiguration: Sendable {
    /// The base URL used for URL generation.
    ///
    /// When set, this value is used as the scheme, host, and port for all
    /// generated URLs. If `nil`, the scheme and host are determined from the
    /// server configuration or request headers.
    ///
    /// Must be a valid URL with at least a scheme and host
    /// (e.g. `https://example.com` or `http://localhost:8080`).
    public var baseURL: URL?

    /// Creates a new URL configuration.
    ///
    /// - Parameter baseURL: The base URL to use for URL generation. Defaults
    ///   to the `APP_URL` environment variable if present.
    public init(baseURL: URL? = Environment.get("APP_URL").flatMap(URL.init(string:))) {
        self.baseURL = baseURL
    }
}

extension Application {
    /// The URL configuration for this application.
    ///
    /// ```swift
    /// // Configure in configure.swift
    /// app.url.baseURL = URL(string: "https://example.com")
    ///
    /// // Uses APP_URL from .env by default
    /// print(app.url.configuration.baseURL)
    /// ```
    public var url: URLConfiguration {
        get {
            self.storage[URLConfigurationKey.self] ?? .init()
        }
        set {
            self.storage[URLConfigurationKey.self] = newValue
        }
    }

    private struct URLConfigurationKey: StorageKey {
        typealias Value = URLConfiguration
    }
}