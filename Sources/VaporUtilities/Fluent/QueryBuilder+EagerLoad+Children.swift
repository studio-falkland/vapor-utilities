import FluentKit

extension QueryBuilder {
    /// Eager-loads a `@Children` relationship while adding constraints to the generated query.
    ///
    /// Fluent's built-in ``with(_:)`` eagerly loads a relationship with no way to restrict *which*
    /// children are fetched. This overload does the same batch fetch that Fluent does internally,
    /// but applies the provided `filter` closure to the related query *before* it runs. The result
    /// is a single, batched `WHERE ... IN (...)` query — no N+1 — that only returns matching
    /// children. Parents that end up with no matching children simply get an empty array.
    ///
    /// ```swift
    /// // Load each author with only the posts published in the last hour.
    /// let authors = try await Author.query(on: db)
    ///     .with(\.$posts) { posts in
    ///         posts.filter(\.$createdAt >= Date().addingTimeInterval(-3600))
    ///     }
    ///     .all()
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Children` relationship on the model.
    ///   - filter: A closure that configures the eager-load query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func with<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ChildrenProperty<Model, Related>>,
        _ filter: @escaping (QueryBuilder<Related>) -> QueryBuilder<Related>
    ) -> Self {
        // Register a shared engine whose closures build the child query and route results back.
        let engine = FilteredEagerLoader<Model, Related>(
            makeQuery: { models, database in
                // Start from the child model, constrained by its parent foreign key.
                let parentKey = Model()[keyPath: relation].parentKey
                let builder = Related.query(on: database)
                let ids = models.compactMap { $0.id }
                switch parentKey {
                case .optional(let optional):
                    builder.filter(optional.appending(path: \.$id) ~~ Set(ids))
                case .required(let required):
                    builder.filter(required.appending(path: \.$id) ~~ Set(ids))
                }
                // Finally apply the user-supplied filter to the eager-load query.
                return filter(builder)
            },
            assign: { models, children in
                // Bucket each matched child back under its owning parent by foreign key.
                let parentKey = Model()[keyPath: relation].parentKey
                for model in models {
                    let id = model[keyPath: relation].fromId!
                    model[keyPath: relation].value = children.filter { child in
                        switch parentKey {
                        case .optional(let optional):
                            return child[keyPath: optional].id == id
                        case .required(let required):
                            return child[keyPath: required].id == id
                        }
                    }
                }
            }
        )
        self.eagerLoaders.append(engine)
        return self
    }
}