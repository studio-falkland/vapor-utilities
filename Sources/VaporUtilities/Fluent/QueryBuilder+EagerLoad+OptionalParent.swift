import FluentKit

extension QueryBuilder {
    /// Eager-loads a `@OptionalParent` relationship while adding constraints to the generated query.
    ///
    /// Behaves like Fluent's built-in ``with(_:)`` for ``OptionalParentProperty`` (a to-one `To?`),
    /// but the `filter` closure is applied to the eager-load query *before* it runs. A related model
    /// that is filtered out (or absent) is assigned `nil`.
    ///
    /// ```swift
    /// let profiles = try await Profile.query(on: db)
    ///     .with(\.$author) { author in
    ///         author.filter(\.$isActive == true)
    ///     }
    ///     .all()
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalParent` relationship on the model.
    ///   - filter: A closure that configures the eager-load query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func with<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalParentProperty<Model, Related>>,
        _ filter: @escaping (QueryBuilder<Related>) -> QueryBuilder<Related>
    ) -> Self {
        // Register a shared engine customized for a to-one `@OptionalParent`.
        let engine = FilteredEagerLoader<Model, Related>(
            makeQuery: { models, database in
                // Query `Related` by the optional referenced IDs stored on each parent model.
                let ids = models.compactMap { $0[keyPath: relation].id }
                let builder = Related.query(on: database).filter(\._$id ~~ Set(ids))
                // Finally apply the user-supplied filter to the eager-load query.
                return filter(builder)
            },
            assign: { models, parents in
                // Index results by id, then set every `OptionalParent` relation.
                let byID = Dictionary(uniqueKeysWithValues: parents.map { ($0.id!, $0) })
                for model in models {
                    // Assign the related object if found; otherwise leave it `.none`.
                    guard let id = model[keyPath: relation].id, let parent = byID[id] else {
                        model[keyPath: relation].value = .some(.none)
                        continue
                    }
                    model[keyPath: relation].value = .some(.some(parent))
                }
            }
        )
        self.eagerLoaders.append(engine)
        return self
    }
}