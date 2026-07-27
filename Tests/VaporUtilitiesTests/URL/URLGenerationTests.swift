import Testing
import Foundation
import Vapor
@testable import VaporUtilities

// MARK: - Helpers

private func withApp(_ body: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    try await body(app)
    try? await app.asyncShutdown()
}

// MARK: - URL Configuration

@Test("URLConfiguration reads APP_URL from environment by default")
func configurationDefaults() {
    let config = URLConfiguration()
    let expected = Environment.get("APP_URL").flatMap(URL.init(string:))
    #expect(config.baseURL == expected)
}

@Test("URLConfiguration accepts custom baseURL")
func configurationCustom() {
    let config = URLConfiguration(baseURL: URL(string: "https://example.com"))
    #expect(config.baseURL == URL(string: "https://example.com"))
}

@Test("URLConfiguration can be nil")
func configurationNil() {
    let config = URLConfiguration(baseURL: nil)
    #expect(config.baseURL == nil)
}

// MARK: - Application URL

@Test("Application url config stores and retrieves baseURL", .timeLimit(.minutes(2)))
func applicationURLConfiguration() async throws {
    try await withApp { app in
        app.url.baseURL = URL(string: "https://example.com")
        #expect(app.url.baseURL == URL(string: "https://example.com"))
    }
}

@Test("Application url config defaults to APP_URL", .timeLimit(.minutes(2)))
func applicationURLConfigurationDefault() async throws {
    try await withApp { app in
        let expected = Environment.get("APP_URL").flatMap(URL.init(string:))
        #expect(app.url.baseURL == expected)
    }
}

@Test("Application url for path with baseURL", .timeLimit(.minutes(2)))
func applicationURLWithBaseURL() async throws {
    try await withApp { app in
        app.url.baseURL = URL(string: "https://example.com")
        let url = app.url(for: "/health")
        #expect(url?.absoluteString == "https://example.com/health")
    }
}

@Test("Application url for path with query", .timeLimit(.minutes(2)))
func applicationURLWithQuery() async throws {
    try await withApp { app in
        app.url.baseURL = URL(string: "https://example.com")
        let url = app.url(for: "/search", query: ["q": "hello", "page": "1"])
        #expect(url != nil)
        #expect(url?.absoluteString.hasPrefix("https://example.com/search?") == true)
        #expect(url?.absoluteString.contains("q=hello") == true)
        #expect(url?.absoluteString.contains("page=1") == true)
    }
}

@Test("Application url normalises path with leading slash", .timeLimit(.minutes(2)))
func applicationURLNormalisesPath() async throws {
    try await withApp { app in
        app.url.baseURL = URL(string: "https://example.com")
        let url = app.url(for: "health")
        #expect(url?.absoluteString == "https://example.com/health")
    }
}

@Test("Application url without baseURL falls back to server config", .timeLimit(.minutes(2)))
func applicationURLWithoutBaseURL() async throws {
    try await withApp { app in
        let url = app.url(for: "/health")
        #expect(url?.absoluteString == "http://127.0.0.1/health")
    }
}

// MARK: - Request URL

@Test("Request absoluteURL with Host header", .timeLimit(.minutes(2)))
func requestAbsoluteURLWithHost() async throws {
    try await withApp { app in
        let request = Request(application: app, method: .GET, url: "/users?page=1", on: app.eventLoopGroup.next())
        request.headers.replaceOrAdd(name: "Host", value: "example.com")
        #expect(request.absoluteURL.absoluteString == "http://example.com/users?page=1")
    }
}

@Test("Request absoluteURL with port in Host header", .timeLimit(.minutes(2)))
func requestAbsoluteURLWithPort() async throws {
    try await withApp { app in
        let request = Request(application: app, method: .GET, url: "/", on: app.eventLoopGroup.next())
        request.headers.replaceOrAdd(name: "Host", value: "example.com:8443")
        #expect(request.absoluteURL.absoluteString == "http://example.com:8443/")
    }
}

@Test("Request url for path with Host header", .timeLimit(.minutes(2)))
func requestURLWithHost() async throws {
    try await withApp { app in
        let request = Request(application: app, method: .GET, url: "/", on: app.eventLoopGroup.next())
        request.headers.replaceOrAdd(name: "Host", value: "example.com")
        let url = request.url(for: "/login")
        #expect(url?.absoluteString == "http://example.com/login")
    }
}

@Test("Request url for path with query", .timeLimit(.minutes(2)))
func requestURLWithQuery() async throws {
    try await withApp { app in
        let request = Request(application: app, method: .GET, url: "/", on: app.eventLoopGroup.next())
        request.headers.replaceOrAdd(name: "Host", value: "example.com")
        let url = request.url(for: "/login", query: ["redirect": "/profile"])
        #expect(url != nil)
        #expect(url?.absoluteString.hasPrefix("http://example.com/login?") == true)
        #expect(url?.absoluteString.contains("redirect=/profile") == true)
    }
}

@Test("Request url uses baseURL when configured", .timeLimit(.minutes(2)))
func requestURLWithBaseURL() async throws {
    try await withApp { app in
        app.url.baseURL = URL(string: "https://example.com")
        let request = Request(application: app, method: .GET, url: "/", on: app.eventLoopGroup.next())
        request.headers.replaceOrAdd(name: "Host", value: "localhost:8080")
        let url = request.url(for: "/health")
        #expect(url?.absoluteString == "https://example.com/health")
    }
}

@Test("Request url normalises path with leading slash", .timeLimit(.minutes(2)))
func requestURLNormalisesPath() async throws {
    try await withApp { app in
        let request = Request(application: app, method: .GET, url: "/", on: app.eventLoopGroup.next())
        request.headers.replaceOrAdd(name: "Host", value: "example.com")
        let url = request.url(for: "login")
        #expect(url?.absoluteString == "http://example.com/login")
    }
}