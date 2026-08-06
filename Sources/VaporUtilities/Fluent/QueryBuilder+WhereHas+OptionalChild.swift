import FluentKit

extension QueryBuilder {
    /// Filters the query to only include models that have an optional child model matching the
    /// given conditions.
    ///
    /// This works identically to ``whereHas(_:_:)`` for `@Children`, but operates on a
    /// `@OptionalChild` relationship. The generated SQL is a correlated `WHERE EXISTS` subquery.
    ///
    /// ```swift
    /// // Get all authors who have a profile with a bio
    /// Author.query(on: db)
    ///     .whereHas(\.$profile) { profile in
    ///         profile.filter(\.$bio != nil)
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalChild` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func whereHas<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalChildProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        // Build the EXISTS subquery. The join condition is child.foreign_key = parent.id,
        // same as for @Children — OptionalChildProperty uses the same RelationParentKey structure.
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: \._$id),
            innerFieldPath: self._optionalChildForeignKey(relation, Model()),
            negated: false,
            closure: closure
        )
        self.query.filters.append(filter)
        return self
    }

    /// Filters the query using `OR` to include models that have an optional child model matching
    /// the given conditions.
    ///
    /// This is the `OR` variant of ``whereHas(_:_:)`` for `@OptionalChild`.
    ///
    /// ```swift
    /// Author.query(on: db)
    ///     .filter(\.$name == "Alice")
    ///     .orWhereHas(\.$profile) { profile in
    ///         profile.filter(\.$bio == "writer")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalChild` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func orWhereHas<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalChildProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: \._$id),
            innerFieldPath: self._optionalChildForeignKey(relation, Model()),
            negated: false,
            closure: closure
        )
        return self._addOrFilter(filter)
    }

    /// Filters the query to exclude models that have an optional child model matching the given
    /// conditions.
    ///
    /// This is the inverse of ``whereHas(_:_:)`` for `@OptionalChild`, generating `WHERE NOT EXISTS`.
    ///
    /// ```swift
    /// // Get all authors who have no profile
    /// Author.query(on: db)
    ///     .whereDoesntHave(\.$profile)
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalChild` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func whereDoesntHave<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalChildProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: \._$id),
            innerFieldPath: self._optionalChildForeignKey(relation, Model()),
            negated: true,
            closure: closure
        )
        self.query.filters.append(filter)
        return self
    }

    /// Filters the query using `OR` to exclude models that have an optional child model matching
    /// the given conditions.
    ///
    /// This is the `OR` variant of ``whereDoesntHave(_:_:)`` for `@OptionalChild`.
    ///
    /// ```swift
    /// Author.query(on: db)
    ///     .filter(\.$name == "Alice")
    ///     .orWhereDoesntHave(\.$profile) { profile in
    ///         profile.filter(\.$bio == "writer")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@OptionalChild` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func orWhereDoesntHave<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalChildProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: \._$id),
            innerFieldPath: self._optionalChildForeignKey(relation, Model()),
            negated: true,
            closure: closure
        )
        return self._addOrFilter(filter)
    }

    /// Resolves the foreign key column on the optional child table that references the parent.
    ///
    /// `@OptionalChild` uses the same `RelationParentKey` structure as `@Children`. This helper
    /// extracts the child's `@Parent` (or `@OptionalParent`) key path and resolves it to the
    /// actual database column name.
    private func _optionalChildForeignKey<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, OptionalChildProperty<Model, Related>>,
        _ model: Model
    ) -> [FieldKey] {
        let child = model[keyPath: relation]
        switch child.parentKey {
        case .required(let keypath):
            return Related.path(for: keypath.appending(path: \.$id))
        case .optional(let keypath):
            return Related.path(for: keypath.appending(path: \.$id))
        }
    }
}