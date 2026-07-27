import Foundation

// MARK: - Data

extension Data {
    /// Returns a base64url-encoded representation of the data.
    ///
    /// Base64url encoding (RFC 4648 §5) replaces `+` with `-` and `/` with `_`
    /// compared to standard base64, and omits trailing `=` padding.
    ///
    /// ```swift
    /// let data = Data("hello".utf8)
    /// print(data.base64URLEncodedString()) // "aGVsbG8"
    /// ```
    ///
    /// - Returns: A base64url-encoded string without padding.
    public func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// Creates data from a base64url-encoded string.
    ///
    /// Accepts both padded and unpadded base64url input, as well as standard
    /// base64 input. Returns `nil` if the input is not valid base64.
    ///
    /// ```swift
    /// let data = Data(base64URLEncoded: "aGVsbG8")
    /// print(String(data: data!, encoding: .utf8)) // "hello"
    /// ```
    ///
    /// - Parameter string: A base64url-encoded string (with or without padding).
    public init?(base64URLEncoded string: String) {
        let base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        let padded = remainder != 0
            ? base64 + String(repeating: "=", count: 4 - remainder)
            : base64

        self.init(base64Encoded: padded)
    }
}