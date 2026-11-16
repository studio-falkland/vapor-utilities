/// A lexicographically sortable key that orders records without rewriting their
/// neighbours.
///
/// A rank is a base-36 string over the alphabet `0-9a-z`. Ranks compare as plain
/// strings, so the database order, the Swift order, and the wire order are always
/// the same:
///
/// ```swift
/// LexoRank("a5")! < LexoRank("a5i")!   // true
/// LexoRank("a5i")! < LexoRank("a6")!   // true
/// ```
///
/// Store a rank in a text column and sort by it. To move a record, compute a rank
/// between its new neighbours and save that record alone:
///
/// ```swift
/// let rank = try LexoRank.between(previous.rank, next.rank)
/// card.rank = rank
/// try await card.save(on: db)
/// ```
///
/// > Important: The column must use a binary collation — `COLLATE "C"` on PostgreSQL,
/// > `BINARY` on SQLite (its default), `utf8mb4_bin` on MySQL. Locale aware collations
/// > can sort digits after letters and will corrupt the order.
public struct LexoRank: Hashable, Sendable, LosslessStringConvertible {
    /// The rank of the first record in an empty list.
    ///
    /// The value is the middle of a four-digit space, which leaves roughly 840,000
    /// appends and 840,000 prepends before either end of the alphabet runs out.
    public static var middle: LexoRank { LexoRank(digits: [18, 0, 0, 0]) }

    /// The smallest expressible rank.
    ///
    /// Nothing sorts before it, so ``previous()`` throws when called on it.
    public static var minimum: LexoRank { LexoRank(digits: [0]) }

    /// The base-36 alphabet in ASCII order, so digit values and character order agree.
    static let alphabet: [UInt8] = Array("0123456789abcdefghijklmnopqrstuvwxyz".utf8)

    /// The number of symbols in the alphabet.
    static let base = 36

    /// The highest digit value, `"z"`.
    static let top: UInt8 = 35

    /// The base-36 digit values (`0...35`) that make up the rank.
    let digits: [UInt8]

    init(digits: [UInt8]) {
        self.digits = digits
    }

    /// Parses a stored or transmitted rank.
    ///
    /// Uppercase letters are folded to lowercase. Returns `nil` for an empty string
    /// or for any character outside `0-9a-zA-Z`.
    public init?(_ description: String) {
        var digits: [UInt8] = []
        digits.reserveCapacity(description.utf8.count)

        // Map every ASCII character onto its digit value and reject anything else, so
        // stray punctuation can never reach the ordering arithmetic.
        for byte in description.utf8 {
            switch byte {
            case 0x30...0x39:
                digits.append(byte - 0x30)
            case 0x41...0x5A:
                digits.append(byte - 0x41 + 10)
            case 0x61...0x7A:
                digits.append(byte - 0x61 + 10)
            default:
                return nil
            }
        }

        guard !digits.isEmpty else { return nil }
        self.digits = digits
    }

    /// The rank as a base-36 string.
    public var description: String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count)
        for digit in digits {
            bytes.append(Self.alphabet[Int(digit)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - Comparable

extension LexoRank: Comparable {
    /// Compares digit by digit, treating a rank that is a prefix of the other as the
    /// smaller one (`"a5" < "a5i"`). This is the same order a text column produces
    /// under a binary collation.
    public static func < (lhs: LexoRank, rhs: LexoRank) -> Bool {
        let shared = min(lhs.digits.count, rhs.digits.count)
        var index = 0

        // The first differing digit decides; the rest of the string is irrelevant.
        while index < shared {
            if lhs.digits[index] != rhs.digits[index] {
                return lhs.digits[index] < rhs.digits[index]
            }
            index += 1
        }

        // One rank is a prefix of the other, so the shorter one sorts first.
        return lhs.digits.count < rhs.digits.count
    }
}

// MARK: - Codable

extension LexoRank: Codable {
    /// Decodes a rank from its base-36 string form.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let rank = LexoRank(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "'\(string)' is not a valid lexorank; expected 0-9a-zA-Z"
            )
        }
        self = rank
    }

    /// Encodes the rank as a single base-36 string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.description)
    }
}
