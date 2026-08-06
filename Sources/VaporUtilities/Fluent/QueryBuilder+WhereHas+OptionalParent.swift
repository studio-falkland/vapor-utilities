import FluentKit

extension QueryBuilder {
    /// Filters the query to only include models whose optional parent model matches the given
    /// conditions.
    ///
    /// This is the `@OptionalParent` equivalent of ``whereHas(_:_:)`` for `@Parent`. It works
    /// identically but handles the case where the foreign key can be `NULL`.
    ///
    /// The generated SQL is a correlated `WHERE EXISTS` subquery on the parent table with the
    /// join condition: `parent_table.id = current_table.foreign_key`.
    ///
    /// ```swift
    /// // Get all profiles whose author is named "Alice"
    /// Profile.query(on: db)
    ///     .whereHas(\.$author) { author in
    ///         author.filter(\.$name == "Alice")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalParent` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func whereHas<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalParentProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        // Build the EXISTS subquery. The outer field is the optional foreign key on the current
        // model (e.g. "author_id"), and the inner field is the ID on the related table.
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: relation.appending(path: \.$id)),
            innerFieldPath: Related.path(for: \._$id),
            negated: false,
            closure: closure
        )
        self.query.filters.append(filter)
        return self
    }

    /// Filters the query using `OR` to include models whose optional parent model matches the
    /// given conditions.
    ///
    /// This is the `OR` variant of ``whereHas(_:_:)`` for `@OptionalParent`.
    ///
    /// ```swift
    /// Profile.query(on: db)
    ///     .filter(\.$bio == "writer")
    ///     .orWhereHas(\.$author) { author in
    ///         author.filter(\.$name == "Alice")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalParent` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func orWhereHas<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalParentProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: relation.appending(path: \.$id)),
            innerFieldPath: Related.path(for: \._$id),
            negated: false,
            closure: closure
        )
        return self._addOrFilter(filter)
    }

    /// Filters the query to exclude models whose optional parent model matches the given
    /// conditions.
    ///
    /// This is the inverse of ``whereHas(_:_:)`` for `@OptionalParent`, generating `WHERE NOT
    /// EXISTS`.
    ///
    /// ```swift
    /// // Get all profiles with no author or whose author is not named "Alice"
    /// Profile.query(on: db)
    ///     .whereDoesntHave(\.$author) { author in
    ///         author.filter(\.$name == "Alice")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalParent` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func whereDoesntHave<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalParentProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: relation.appending(path: \.$id)),
            innerFieldPath: Related.path(for: \._$id),
            negated: true,
            closure: closure
        )
        self.query.filters.append(filter)
        return self
    }

    /// Filters the query using `OR` to exclude models whose optional parent model matches the
    /// given conditions.
    ///
    /// This is the `OR` variant of ``whereDoesntHave(_:_:)`` for `@OptionalParent`.
    ///
    /// ```swift
    /// Profile.query(on: db)
    ///     .filter(\.$bio == "writer")
    ///     .orWhereDoesntHave(\.$author)
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalParent` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func orWhereDoesntHave<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalParentProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: relation.appending(path: \.$id)),
            innerFieldPath: Related.path(for: \._$id),
            negated: true,
            closure: closure
        )
        return self._addOrFilter(filter)
    }
}