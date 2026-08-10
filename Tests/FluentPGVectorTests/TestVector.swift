@preconcurrency import Pgvector

/// Provides a `Pgvector.Vector` value for use in test data without requiring
/// the test file to import `Pgvector` (which would collide with `Fields.Vector`).
enum TestVector {
    /// A small vector for testing, equivalent to `[0.1, 0.2]`.
    static let embedding = Pgvector.Vector([Float(0.1), Float(0.2)])
}