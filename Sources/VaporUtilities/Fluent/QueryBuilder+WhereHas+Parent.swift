import FluentKit

extension QueryBuilder {
    /// Filters the query to only include models whose parent model matches the given conditions.
    ///
    /// This is the `@Parent` equivalent of ``whereHas(_:_:)`` for `@Children`. Instead of checking
    /// for existence of children, it checks for existence of a parent record. The generated SQL is
    /// a correlated `WHERE EXISTS` subquery on the parent table.
    ///
    /// The join condition is reversed compared to `@Children`: `parent_table.id = current_table.foreign_key`.
    ///
    /// ```swift
    /// // Get all posts whose author is named "Alice"
    /// Post.query(on: db)
    ///     .whereHas(\.$author) { author in
    ///         author.filter(\.$name == "Alice")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Parent` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func whereHas<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ParentProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        // Build the EXISTS subquery. The outer field is the foreign key on the current model
        // (e.g. "author_id"), and the inner field is the ID on the related table (e.g. "id").
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: relation.appending(path: \.$id)),
            innerFieldPath: Related.path(for: \._$id),
            negated: false,
            closure: closure
        )
        self.query.filters.append(filter)
        return self
    }

    /// Filters the query using `OR` to include models whose parent model matches the given
    /// conditions.
    ///
    /// This is the `OR` variant of ``whereHas(_:_:)`` for `@Parent`.
    ///
    /// ```swift
    /// Post.query(on: db)
    ///     .filter(\.$status == "published")
    ///     .orWhereHas(\.$author) { author in
    ///         author.filter(\.$name == "Alice")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Parent` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func orWhereHas<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ParentProperty<Model, Related>>,
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

    /// Filters the query to exclude models whose parent model matches the given conditions.
    ///
    /// This is the inverse of ``whereHas(_:_:)`` for `@Parent`, generating `WHERE NOT EXISTS`.
    ///
    /// ```swift
    /// // Get all posts whose author is not named "Alice"
    /// Post.query(on: db)
    ///     .whereDoesntHave(\.$author) { author in
    ///         author.filter(\.$name == "Alice")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Parent` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func whereDoesntHave<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ParentProperty<Model, Related>>,
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

    /// Filters the query using `OR` to exclude models whose parent model matches the given
    /// conditions.
    ///
    /// This is the `OR` variant of ``whereDoesntHave(_:_:)`` for `@Parent`.
    ///
    /// ```swift
    /// Post.query(on: db)
    ///     .filter(\.$status == "published")
    ///     .orWhereDoesntHave(\.$author)
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Parent` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func orWhereDoesntHave<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ParentProperty<Model, Related>>,
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