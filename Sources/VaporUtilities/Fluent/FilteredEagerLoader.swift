import FluentKit

/// Shared engine for filtered eager loads across all relation types.
///
/// Each relation differs only in two ways, both supplied as closures at registration time:
/// 1. `makeQuery` — how to build the relationship-constrained `QueryBuilder` (foreign-key filter,
///    pivot join, and the user's `filter` closure).
/// 2. `assign` — how to map the fetched `[To]` results back onto the parent models.
///
/// Everything else — the `EventLoopFuture` bridge, the `AnyModel` erasure, the batch fetch, and
/// the test-facing `childQuery` accessor — is shared in this one type.
struct FilteredEagerLoader<From, To>: EagerLoader, @unchecked Sendable
    where From: Model, To: Model
{
    // Pin `Model` to the parent for Fluent's `EagerLoader`, and note `To` for the child/related.
    typealias Model = From

    // Build the relationship-constrained query (including the user's filter) for given parents.
    let makeQuery: ([From], any Database) -> QueryBuilder<To>

    // Route the fetched `[To]` results back onto the parent models (may throw on bad joins).
    let assign: ([From], [To]) throws -> Void

    func run(models: [From], on database: any Database) -> EventLoopFuture<Void> {
        // Bridge the synchronous protocol entry point to the async work.
        database.eventLoop.makeFutureWithTask {
            try await self.runAsync(models: models, on: database)
        }
    }

    /// FluentKit provides a default `anyRun` internally, but it is `internal` to FluentKit
    /// and thus not visible from this module, so we provide it here.
    func anyRun(models: [any AnyModel], on database: any Database) -> EventLoopFuture<Void> {
        // Erase the model array down to the concrete `From` type, then run.
        self.run(models: models.map { $0 as! From }, on: database)
    }

    private func runAsync(models: [From], on database: any Database) async throws {
        // Execute the constrained query once, then map results back onto the parents.
        let result = try await self.makeQuery(models, database).all()
        try self.assign(models, result)
    }

    /// Builds the same query the loader would run, exposed for tests to serialize its SQL.
    func childQuery(models: [From], on database: any Database) -> QueryBuilder<To> {
        self.makeQuery(models, database)
    }
}