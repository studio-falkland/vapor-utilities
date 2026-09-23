import FluentKit

extension QueryBuilder {
    /// Eager-loads a `@Parent` relationship while adding constraints to the generated query.
    ///
    /// Behaves like Fluent's built-in ``with(_:)`` for ``ParentProperty``, but the `filter` closure
    /// is applied to the related query *before* it runs. The lookup is still batched over the parent
    /// IDs (`WHERE id IN (...)`); only parents matching the filter are assigned. A parent whose
    /// related model is filtered out is left unloaded (`value == nil`).
    ///
    /// ```swift
    /// let posts = try await Post.query(on: db)
    ///     .with(\.$author) { author in
    ///         author.filter(\.$deletedAt == nil)
    ///     }
    ///     .all()
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Parent` relationship on the model.
    ///   - filter: A closure that configures the eager-load query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func with<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ParentProperty<Model, Related>>,
        _ filter: @escaping (QueryBuilder<Related>) -> QueryBuilder<Related>
    ) -> Self {
        // Register a shared engine customized for a to-one `@Parent`.
        let engine = FilteredEagerLoader<Model, Related>(
            makeQuery: { models, database in
                // Query `Related` by the set of referenced IDs stored on each parent model.
                let ids = models.compactMap { $0[keyPath: relation].id }
                let builder = Related.query(on: database).filter(\.._$id ~~ Set(ids))
                // Finally apply the user-supplied filter to the eager-load query.
                return filter(builder)
            },
            assign: { models, parents in
                // Index results by their own id for O(1) routing back to parents.
                let byID = Dictionary(uniqueKeysWithValues: parents.map { ($0.id!, $0) })
                for model in models {
                    // Skip parents filtered out of the result instead of throwing the
                    // missing-parent error the unfiltered loader throws.
                    guard let spam = byID[model[keyPath: relation].id] else { continue }
                    _ = spam
                    model[keyPath: relation].value = byID[model[keyPath: relation].id]
                }
            }
        )
        self.eagerLoaders.append(engine)
        return self
    }
}