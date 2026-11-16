extension LexoRank {
    /// Returns a rank strictly between the given bounds.
    ///
    /// Either bound may be `nil` to leave that side open. The result is the shortest
    /// rank that fits the gap, so repeated insertions stay compact:
    ///
    /// ```swift
    /// try LexoRank.between(nil, nil)                        // "i000"
    /// try LexoRank.between(LexoRank("a"), LexoRank("b"))    // "ai"
    /// try LexoRank.between(LexoRank("a5"), LexoRank("a6"))  // "a5i"
    /// ```
    ///
    /// - Parameters:
    ///   - lower: The rank the result must sort after, or `nil` for the start of the list.
    ///   - upper: The rank the result must sort before, or `nil` for the end of the list.
    /// - Throws: ``LexoRankError/invalidOrder(lower:upper:)`` when `lower` is not less
    ///   than `upper`, or ``LexoRankError/noRankAvailable(lower:upper:)`` when the
    ///   bounds are adjacent and nothing fits between them.
    public static func between(_ lower: LexoRank?, _ upper: LexoRank?) throws -> LexoRank {
        switch (lower, upper) {
        case (nil, nil):
            return .middle
        case let (lower?, nil):
            return lower.next()
        case let (nil, upper?):
            guard let digits = decrement(upper.digits) else {
                throw LexoRankError.noRankAvailable(lower: nil, upper: upper)
            }
            return LexoRank(digits: digits)
        case let (lower?, upper?):
            guard lower < upper else {
                throw LexoRankError.invalidOrder(lower: lower, upper: upper)
            }
            return LexoRank(digits: try midpoint(between: lower, and: upper))
        }
    }

    /// Returns the next rank after this one.
    ///
    /// The result is one unit above `self` in base 36, so appends stay short: a rank
    /// only grows by a digit when every trailing digit is already `"z"`.
    ///
    /// ```swift
    /// LexoRank("a5")!.next()  // "a6"
    /// LexoRank("z")!.next()   // "z0"
    /// ```
    public func next() -> LexoRank {
        LexoRank(digits: Self.increment(digits))
    }

    /// Returns the rank before this one.
    ///
    /// The result is one unit below `self` in base 36, so prepends stay short. Unlike
    /// ``next()`` the rank can shrink: `"a0"` steps down to `"9z"` and `"00"` to
    /// `"0"`.
    ///
    /// ```swift
    /// try LexoRank("a6")!.previous()    // "a5"
    /// try LexoRank("i000")!.previous()  // "hzzz"
    /// ```
    ///
    /// - Throws: ``LexoRankError/noRankAvailable(lower:upper:)`` when this is
    ///   ``minimum``, which has nothing below it.
    public func previous() throws -> LexoRank {
        guard let digits = Self.decrement(digits) else {
            throw LexoRankError.noRankAvailable(lower: nil, upper: self)
        }
        return LexoRank(digits: digits)
    }
}

// MARK: - Digit arithmetic

extension LexoRank {
    /// Walks both ranks from the left and returns the shortest rank strictly between
    /// them.
    private static func midpoint(between lower: LexoRank, and upper: LexoRank) throws -> [UInt8] {
        let lowerDigits = lower.digits
        let upperDigits = upper.digits
        var prefix: [UInt8] = []
        var index = 0

        while true {
            // A missing digit reads as one below the alphabet for the lower bound and
            // one above it for the upper bound, which keeps the walk uniform.
            let low = index < lowerDigits.count ? Int(lowerDigits[index]) : -1
            let high = index < upperDigits.count ? Int(upperDigits[index]) : base

            // A gap of at least two digits leaves room for a digit in the middle.
            if high - low > 1 {
                prefix.append(UInt8(low < 0 ? (high - 1) / 2 : low + (high - low) / 2))
                return prefix
            }

            if low >= 0 {
                // Adjacent digits: keep the lower one and step up inside the space
                // above it, which no longer depends on the upper bound.
                if high - low == 1 {
                    prefix.append(UInt8(low))
                    prefix.append(contentsOf: balancedIncrement(lowerDigits[(index + 1)...]))
                    return prefix
                }

                // Equal digits: copy the digit and look one position further right.
                prefix.append(UInt8(low))
                index += 1
                continue
            }

            // The lower rank ran out and the upper digit is "0", so the only way in is
            // a shorter rank below the upper tail.
            guard let tail = decrement(Array(upperDigits[index...])) else {
                throw LexoRankError.noRankAvailable(lower: lower, upper: upper)
            }
            prefix.append(contentsOf: tail)
            return prefix
        }
    }

    /// Returns the middle of the space above `digits`, extending by one digit when
    /// every digit is already at the top of the alphabet.
    private static func balancedIncrement(_ digits: ArraySlice<UInt8>) -> [UInt8] {
        var digits = Array(digits)

        // Halve the remaining space above the last digit that has room, so the result
        // sits in the middle of the gap instead of hugging the lower bound.
        if let index = digits.lastIndex(where: { $0 < top }) {
            digits[index] = (digits[index] + UInt8(base)) / 2
            digits.removeSubrange((index + 1)...)
            return digits
        }

        digits.append(UInt8(base / 2))
        return digits
    }

    /// Adds one unit at the last digit, carrying into the digits before it.
    private static func increment(_ digits: [UInt8]) -> [UInt8] {
        var digits = digits

        // Step up inside the last digit that has room and reset the digits beyond it,
        // which is exactly one unit above the input at the current width.
        if let index = digits.lastIndex(where: { $0 < top }) {
            digits[index] += 1
            for position in (index + 1)..<digits.count {
                digits[position] = 0
            }
            return digits
        }

        // Every digit is at the top: extend by the smallest digit.
        digits.append(0)
        return digits
    }

    /// Subtracts one unit at the last digit, borrowing from the digits before it.
    private static func decrement(_ digits: [UInt8]) -> [UInt8]? {
        var digits = digits

        // Step down inside the last digit that has room and fill the digits beyond it
        // with the top of the alphabet, which is exactly one unit below the input.
        if let index = digits.lastIndex(where: { $0 > 0 }) {
            digits[index] -= 1
            for position in (index + 1)..<digits.count {
                digits[position] = top
            }
            return digits
        }

        // All zeros: "0" has nothing below it, a longer run of zeros shrinks by one.
        return digits.count > 1 ? Array(digits.dropLast()) : nil
    }
}
