import FluentKit

extension QueryBuilder {
    /// Eager-loads a `@OptionalChild` relationship while adding constraints to the generated query.
    ///
    /// Behaves like Fluent's built-in ``with(_:)`` for ``OptionalChildProperty`` (a to-one `To?`),
    /// but the `filter` closure is applied to the eager-load query *before* it runs. When a child
    /// is filtered out, `value` is set to `nil`.
    ///
    /// ```swift
    /// let authors = try await Author.query(on: db)
    ///     .with(\.$profile) { profile in
    ///         profile.filter(\.$isPublic == true)
    ///     }
    ///     .all()
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalChild` relationship on the model.
    ///   - filter: A closure that configures the eager-load query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func with<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalChildProperty<Model, Related>>,
        _ filter: @escaping (QueryBuilder<Related>) -> QueryBuilder<Related>
    ) -> Self {
        // Register a shared engine; the child query is identical to `@Children`.
        let engine = FilteredEagerLoader<Model, Related>(
            makeQuery: { models, database in
                // Start from the child model, constrained by its parent foreign key.
                let parentKey = Model()[keyPath: relation].parentKey
                let builder = Related.query(on: database)
                let ids = models.compactMap { $0.id }
                switch parentKey {
                case .optional(let optional):
                    builder.filter(optional.appending(path: \..$id) ~~ Set(ids))
                case .required(let required):
                    builder.filter(required.appending(path: \..$id) ~~ Set(ids))
                }
                // Finally apply the user-supplied filter to the eager-load query.
                return filter(builder)
            },
            assign: { models, children in
                // A `@OptionalChild` is to-one: assign the first matching child, else `nil`.
                let parentKey = Model()[keyPath: relation].parentKey
                for model in models {
                    let id = model[keyPath: relation].fromId!
                    model[keyPath: relation].value = children.first { child in
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