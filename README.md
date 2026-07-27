<p align="center">
<img src="./Documentation/logo.svg" width="340" />
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white" alt="Swift 6.0+"></a>
  <a href="https://swift.org/package-manager"><img src="https://img.shields.io/badge/SPM-compatible-4BC51D?logo=swift&logoColor=white" alt="SPM Compatible"></a>
  <a href="https://github.com/vapor/vapor"><img src="https://img.shields.io/badge/Vapor-4-6DBEEB?logo=vapor&logoColor=white" alt="Vapor 4"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-EUPL--1.2-blue.svg" alt="License: EUPL-1.2"></a>
</p>

# VaporUtilities

Utility extensions for [Vapor](https://github.com/vapor/vapor) applications.

## Installation

Add the package to your Vapor project's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
    .package(url: "https://github.com/studio-falkland/vapor-utilities.git", from: "1.0.0"),
],
```

Then add `VaporUtilities` to your target dependencies:

```swift
.target(name: "App", dependencies: [
    .product(name: "Vapor", package: "vapor"),
    .product(name: "VaporUtilities", package: "vapor-utilities"),
]),
```

## Base64URL

Encode and decode data using the base64url alphabet (RFC 4648 §5), which replaces `+` and `/` with `-` and `_` and omits padding.

```swift
import VaporUtilities

// Data
Data("hello".utf8).base64URLEncodedString()        // "aGVsbG8"
Data(base64URLEncoded: "aGVsbG8")                    // "hello" as Data

// String
"hello".base64URLEncodedString()                    // "aGVsbG8"
"hello".base64URLEncodedBytes()                     // [97, 71, 86, 115, 98, 71, 56]
"aGVsbG8".base64URLDecodedData                      // "hello" as Data

// Byte array
[UInt8](decodingBase64URL: "aGVsbG8")                // [104, 101, 108, 108, 111]
[UInt8](decodingBase64URL: [97, 71, 86, 115, 98, 71, 56] as [UInt8])  // [104, 101, 108, 108, 111]

// Substring
"hello world".prefix(5).base64URLEncodedString()     // "aGVsbG8"
```

## URL Generation

Build absolute URLs from the current request or application configuration.

```swift
import VaporUtilities

// The full request URL
request.absoluteURL                             // "https://example.com/users?page=1"

// Build a URL relative to the request
request.url(for: "/login", query: ["r": "/"])   // "https://example.com/login?r=%2F"

// From the application configuration
app.url(for: "/health")                          // "https://example.com/health"
```

### Configuration

Set `app.url.baseURL` to override the automatic scheme/host detection. This is
useful for production deployments behind a reverse proxy.

```swift
app.url.baseURL = URL(string: "https://example.com")
```

The `APP_URL` environment variable is read automatically and used as the default.

```env
APP_URL=https://example.com
```

## Running Tests

```bash
swift test
```

## Authors

This library is developed by Lei Nelissen at Studio Falkland.

![Studio Falkland](./Documentation/falkland-logo-long-orange.svg)

## License

Licensed under the **European Union Public Licence v. 1.2 (EUPL-1.2)**. See [`LICENSE`](LICENSE) for the full text.
