# VaporUtilities — Agent Reference

## Identity

SPM library providing utility extensions for Vapor 4 applications.

---

## Modules

| Module | Description |
|---|---|
| `VaporUtilities` | Base64URL encoding/decoding, URL generation helpers |

---

## Dependencies

- `vapor/vapor` from 4.121.4

---

## Build & Test

```
swift build
swift test
```

---

## Public API

### Base64URL

- `Data.base64URLEncodedString()` — encode to RFC 4648 §5 without padding
- `Data(base64URLEncoded:)` — decode from base64url string (nil on failure)
- `String.base64URLEncodedString()` — encode a string directly
- `String.base64URLEncodedBytes()` — encode as base64url bytes
- `String.base64URLDecodedData` — convenience property
- `[UInt8].base64URLEncodedString()` — encode a byte array
- `[UInt8].base64URLEncodedBytes()` — encode a byte array as bytes
- `[UInt8](decodingBase64URL:)` — decode from string or bytes
- `Substring.base64URLEncodedString()` — encode a substring
- `Substring.base64URLEncodedBytes()` — encode a substring as bytes

### URL Generation

- `Request.absoluteURL` — full URL of the current request
- `Request.url(for:query:)` — build URL relative to request
- `Application.url(for:query:)` — build URL from server config

---

## Platform

macOS 15+. Swift 6.0 tools.