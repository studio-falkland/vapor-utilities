import FluentKit

extension QueryBuilder {
    /// Eager-loads a `@Siblings` relationship while adding constraints to the generated query.
    ///
    /// Behaves like Fluent's built-in ``with(_:)`` for ``SiblingsProperty`` (a many-to-many via a
    /// pivot `Through` model), but the `filter` closure is applied to the eager-load query *before*
    /// it runs. The join over the pivot is preserved; only siblings matching the filter are included
    /// in the result. Parents with no matching siblings get an empty array.
    ///
    /// ```swift
    /// let planets = try await Planet.query(on: db)
    ///     .with(\.$tags) { tags in
    ///         tags.filter(\.$kind == "featured")
    ///     }
    ///     .all()
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Siblings` relationship on the model.
    ///   - filter: A closure that configures the eager-load query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func with<Related: FluentKit.Model, Through: FluentKit.Model>(
        _ relation: KeyPath<Model, SiblingsProperty<Model, Related, Through>>,
        _ filter: @escaping (QueryBuilder<Related>) -> QueryBuilder<Related>
    ) -> Self {
        // Register a shared engine customized for a many-to-many `@Siblings`.
        let engine = FilteredEagerLoader<Model, Related>(
            makeQuery: { models, database in
                // Join `Related` through the pivot, constraining on the pivot's parent foreign key.
                let from = Model()[keyPath: relation].from
                let to = Model()[keyPath: relation].to
                let builder = Related.query(on: database)
                    .join(Through.self, on: \Related._$id == to.appending(path: \..$id))
                    .filter(Through.self, from.appending(path: \..$id) ~~ Set(models.compactMap { $0.id }))
                // Finally apply the user-supplied filter to the eager-load query.
                return filter(builder)
            },
            assign: { models, siblings in
                // Group each sibling under its parent id via the joined pivot foreign key.
                let from = Model()[keyPath: relation].from
                var map: [Model.IDValue: [Related]] = [:]
                for sibling in siblings {
                    let fromID = try sibling.joined(Through.self)[keyPath: from].id
                    map[fromID, default: []].append(sibling)
                }
                // Assign each parent's matching siblings, defaulting to an empty array.
                for model in models {
                    guard let id = model.id else { continue }
                    model[keyPath: relation].value = map[id] ?? []
                }
            }
        )
        self.eagerLoaders.append(engine)
        return self
    }
}