import Configuration
import Foundation
import Vapor

/// Configuration for URL generation in a Vapor application.
///
/// The base URL is read from the application's `ConfigReader` under the
/// `app.url` key, which the environment variables provider maps from
/// `APP_URL`. This is useful for production deployments behind a reverse
/// proxy where the server's bind address differs from the public URL.
///
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
    /// - Parameter baseURL: The base URL to use for URL generation.
    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }
}

extension Application {
    /// The URL configuration for this application.
    ///
    /// Reads `app.url` from the application's configuration. The environment
    /// variables provider maps `APP_URL` to that key.
    ///
    /// ```env
    /// APP_URL=https://example.com
    /// ```
    public var url: URLConfiguration {
        URLConfiguration(
            baseURL: self.configReader.string(forKey: "app.url").flatMap(URL.init(string:))
        )
    }
}
