import Foundation

// MARK: - String

extension String {
    /// Returns the base64url-encoded bytes of this string's UTF-8 representation.
    ///
    /// ```swift
    /// print("hello".base64URLEncodedBytes()) // [97, 71, 86, 115, 98, 71, 56]
    /// ```
    public func base64URLEncodedBytes() -> [UInt8] {
        Data(self.utf8).base64URLEncodedString().utf8.map { UInt8($0) }
    }

    /// Returns the base64url-encoded string of this string's UTF-8 representation.
    ///
    /// ```swift
    /// print("hello".base64URLEncodedString()) // "aGVsbG8"
    /// ```
    public func base64URLEncodedString() -> String {
        Data(self.utf8).base64URLEncodedString()
    }

    /// Attempts to decode this string as base64url-encoded data.
    ///
    /// ```swift
    /// let data = "aGVsbG8".base64URLDecodedData
    /// print(String(data: data!, encoding: .utf8)) // "hello"
    /// ```
    public var base64URLDecodedData: Data? {
        Data(base64URLEncoded: self)
    }
}

// MARK: - Substring

extension Substring {
    /// Returns the base64url-encoded bytes of this substring's UTF-8 representation.
    public func base64URLEncodedBytes() -> [UInt8] {
        Data(self.utf8).base64URLEncodedString().utf8.map { UInt8($0) }
    }

    /// Returns the base64url-encoded string of this substring's UTF-8 representation.
    public func base64URLEncodedString() -> String {
        Data(self.utf8).base64URLEncodedString()
    }
}