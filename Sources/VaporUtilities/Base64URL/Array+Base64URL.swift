import Foundation

// MARK: - RandomAccessCollection

extension RandomAccessCollection where Element == UInt8, Index == Int {
    /// Returns the base64url-encoded bytes of this collection.
    ///
    /// ```swift
    /// let bytes: [UInt8] = [0x66, 0x6f, 0x6f]
    /// print(bytes.base64URLEncodedBytes()) // [90, 109, 57, 118]
    /// ```
    public func base64URLEncodedBytes() -> [UInt8] {
        Data(self).base64URLEncodedString().utf8.map { UInt8($0) }
    }

    /// Returns the base64url-encoded string of this collection.
    ///
    /// ```swift
    /// let bytes: [UInt8] = [0x66, 0x6f, 0x6f]
    /// print(bytes.base64URLEncodedString()) // "Zm9v"
    /// ```
    public func base64URLEncodedString() -> String {
        Data(self).base64URLEncodedString()
    }
}

// MARK: - Array

extension Array where Element == UInt8 {
    /// Decodes a base64url-encoded string into a byte array.
    ///
    /// Returns `nil` if the input is not valid base64url.
    ///
    /// ```swift
    /// let bytes = [UInt8](decodingBase64URL: "aGVsbG8")
    /// print(String(bytes: bytes!, encoding: .utf8)) // "hello"
    /// ```
    public init?(decodingBase64URL string: String) {
        guard let data = Data(base64URLEncoded: string) else { return nil }
        self = [UInt8](data)
    }

    /// Decodes a base64url-encoded byte sequence into a byte array.
    ///
    /// Returns `nil` if the input is not valid base64url.
    ///
    /// ```swift
    /// let encoded: [UInt8] = [97, 71, 86, 115, 98, 71, 56]
    /// let bytes = [UInt8](decodingBase64URL: encoded)
    /// ```
    public init?<C>(decodingBase64URL bytes: C) where C: RandomAccessCollection, C.Element == UInt8, C.Index == Int {
        guard let string = String(bytes: bytes, encoding: .ascii) else { return nil }
        self.init(decodingBase64URL: string)
    }
}