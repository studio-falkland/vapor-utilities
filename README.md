<p align="center">
<img src="./Documentation/logo.svg" width="340" />
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white" alt="Swift 6.0+"></a>
  <a href="https://swift.org/package-manager"><img src="https://img.shields.io/badge/SPM-compatible-4BC51D?logo=swift&logoColor=white" alt="SPM Compatible"></a>
  <a href="https://github.com/vapor/vapor"><img src="https://img.shields.io/badge/Vapor-4-6DBEEB?logo=vapor&logoColor=white" alt="Vapor 4"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-EUPL--1.2-blue.svg" alt="License: EUPL-1.2"></a>
</p>

Utility extensions for [Vapor](https://github.com/vapor/vapor) applications.

## Installation

Add the package to your Vapor project's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
    .package(url: "https://github.com/studio-falkland/vapor-utilities.git", from: "1.0.0"),
],
```

Then add the products you need to your target dependencies:

```swift
.target(name: "App", dependencies: [
    .product(name: "Vapor", package: "vapor"),
    .product(name: "VaporUtilities", package: "vapor-utilities"),
    .product(name: "FluentPGVector", package: "vapor-utilities"),
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

## Fluent

Extensions for [Fluent](https://github.com/vapor/fluent-kit) `QueryBuilder`.

### Chunk

Iterate through large result sets in discrete batches without loading everything
into memory at once. Each chunk is fetched, processed with the closure, then
discarded before the next chunk is fetched.

```swift
import VaporUtilities

try await User.query(on: db)
    .sort(\.$id, .ascending)
    .chunk(size: 100) { chunk in
        for user in chunk {
            // process each user
        }
    }
```

> Tip: Always apply a `sort` before calling `chunk` to ensure consistent
> ordering across pages. Without a sort, the order is undefined.

### Chunk with cursor

For large datasets, the offset/limit approach above slows down as the offset
grows. Use the cursor-based overload to avoid this by filtering with `WHERE cursor > ?` instead of `OFFSET`.

The cursor column value type must be `Comparable` (e.g. `Int`, `Date`, `String`, or `UUID`).
`UUID` conforms to `Comparable` on macOS 14+ / iOS 17+ (this package targets macOS 15).

```swift
import VaporUtilities

try await User.query(on: db)
    .filter(\.$status == "active")
    .chunk(size: 100, cursor: \.$id, order: .ascending) { chunk in
        for user in chunk {
            // process each user
        }
    }
```

For models with a `Comparable` ID type (including `UUID` on macOS 14+), use the
`chunkById` convenience which defaults to the model's ID column:

```swift
try await User.query(on: db)
    .filter(\.$status == "active")
    .chunkById(size: 100) { chunk in
        for user in chunk {
            // process each user
        }
    }
```

### Where Has

Filter a model based on the existence (or absence) of related records matching
conditions. Works with `@Children`, `@OptionalChild`, `@Parent`, and
`@OptionalParent` relationships. Generates correlated `EXISTS` / `NOT EXISTS`
subqueries.

```swift
import VaporUtilities

// Authors who have published posts
Author.query(on: db)
    .whereHas(\.$posts) { post in
        post.filter(\.$status == "published")
    }

// Authors who have no published posts
Author.query(on: db)
    .whereDoesntHave(\.$posts) { post in
        post.filter(\.$status == "published")
    }

// Posts whose author is named "Alice"
Post.query(on: db)
    .whereHas(\.$author) { author in
        author.filter(\.$name == "Alice")
    }

// Authors with a profile whose bio is "writer"
Author.query(on: db)
    .whereHas(\.$profile) { profile in
        profile.filter(\.$bio == "writer")
    }

// OR variants combine with existing filters using OR
Author.query(on: db)
    .filter(\.$name == "Alice")
    .orWhereHas(\.$posts) { post in
        post.filter(\.$status == "published")
    }
```

## FluentPGVector

Fluent-native pgvector support: a `@Vector` property wrapper and `QueryBuilder` extensions
for cosine distance search with the `<=>` operator.

### Migration

```swift
import FluentPGVector

try await database.schema("chunks")
    .field("embedding", .vector(dimensions: 2560))
    .create()
```

### Model

```swift
final class Chunk: Model {
    @Vector(key: "embedding", dimensions: 2560)
    var embedding: [Double]?
}
```

### Sort by cosine distance

Orders results by `field <=> ?::vector` without selecting the distance as a column.

```swift
Chunk.query(on: db)
    .filter(\.$source == "example.com")
    .sort(Chunk().$embedding.key, cosineDistanceTo: queryVector)
    .limit(10)
    .all()
```

### Search with distance returned

SELECTs the distance as a computed column and returns `(Model, Double)` tuples.

```swift
let results = try await Chunk.query(on: db)
    .filter(\.$source == "example.com")
    .allWithDistance(Chunk().$embedding.key, to: queryVector, limit: 10)
// results: [(PageChunk, Double)]
```

> [!IMPORTANT]
> Before using this library, you must install the [pgvector](https://github.com/pgvector/pgvector)
> extension in your PostgreSQL database:
>
> ```sql
> CREATE EXTENSION vector;
> ```
>
> You must also register the pgvector type OID
> **once during app startup** before any query that selects a `@Vector` column:
>
> ```swift
> // In configure.swift:
> try await FPGVector.registerVectorTypes(on: app.db)
> ```
>
> Without this call, decoding a `vector` column crashes with `FluentError.invalidField`.
> The `allWithDistance(_:to:limit:)` method calls this automatically, but regular
> `Model.query(on: db).all()` queries do not.

## Running Tests

```bash
swift test
```

## Authors

This library is developed by Lei Nelissen at Studio Falkland.

![Studio Falkland](./Documentation/falkland-logo-long-orange.svg)

## License

Licensed under the **European Union Public Licence v. 1.2 (EUPL-1.2)**. See [`LICENSE`](LICENSE) for the full text.
