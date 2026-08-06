import FluentKit

extension QueryBuilder {
    /// Filters the query to only include models that have at least one related child model
    /// matching the given conditions.
    ///
    /// Generates a correlated `WHERE EXISTS` subquery to efficiently filter the parent model
    /// based on the existence of related children.
    ///
    /// The subquery joins the child table to the parent table using the foreign key defined by
    /// the `@Children` relationship. Any filters applied inside the `closure` are added to the
    /// subquery's `WHERE` clause.
    ///
    /// ```swift
    /// // Get all authors who have published posts
    /// Author.query(on: db)
    ///     .whereHas(\.$posts) { post in
    ///         post.filter(\.$status == "published")
    ///     }
    /// ```
    ///
    /// To only check for existence without additional conditions, omit the closure:
    ///
    /// ```swift
    /// // Get all authors who have any posts at all
    /// Author.query(on: db)
    ///     .whereHas(\.$posts)
    /// ```
    ///
    /// You can chain `whereHas` with other filters — the subquery is combined with `AND`:
    ///
    /// ```swift
    /// Author.query(on: db)
    ///     .filter(\.$name == "Alice")
    ///     .whereHas(\.$posts) { post in
    ///         post.filter(\.$status == "published")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Children` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    ///     Defaults to an identity closure (no additional filters).
    /// - Returns: `self` for chaining.
    @discardableResult
    public func whereHas<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ChildrenProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        // Build the EXISTS subquery with the join condition and user's filters.
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: \._$id),
            innerFieldPath: self._childrenForeignKey(relation, Model()),
            negated: false,
            closure: closure
        )
        // Add the subquery as a new filter, combined with AND to any existing filters.
        self.query.filters.append(filter)
        return self
    }

    /// Filters the query using `OR` to include models that have at least one related child model
    /// matching the given conditions.
    ///
    /// This is the `OR` variant of ``whereHas(_:_:)``. The existing filters and the new subquery
    /// are wrapped in an `OR` group.
    ///
    /// ```swift
    /// // Get all authors who have published posts OR are named "Alice"
    /// Author.query(on: db)
    ///     .filter(\.$name == "Alice")
    ///     .orWhereHas(\.$posts) { post in
    ///         post.filter(\.$status == "published")
    ///     }
    /// ```
    ///
    /// Multiple `orWhereHas` calls chain into a single flat OR group:
    ///
    /// ```swift
    /// Author.query(on: db)
    ///     .whereHas(\.$posts) { post in post.filter(\.$status == "published") }
    ///     .orWhereHas(\.$posts) { post in post.filter(\.$status == "draft") }
    ///     .orWhereHas(\.$posts) { post in post.filter(\.$status == "archived") }
    /// // WHERE EXISTS (... "published") OR EXISTS (... "draft") OR EXISTS (... "archived")
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Children` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func orWhereHas<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ChildrenProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: \._$id),
            innerFieldPath: self._childrenForeignKey(relation, Model()),
            negated: false,
            closure: closure
        )
        // Use _addOrFilter to wrap existing filters + this one in an OR group.
        return self._addOrFilter(filter)
    }

    /// Filters the query to exclude models that have related child models matching the given
    /// conditions.
    ///
    /// This is the inverse of ``whereHas(_:_:)``. It generates a `WHERE NOT EXISTS` subquery.
    ///
    /// ```swift
    /// // Get all authors who have no published posts
    /// Author.query(on: db)
    ///     .whereDoesntHave(\.$posts) { post in
    ///         post.filter(\.$status == "published")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Children` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func whereDoesntHave<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ChildrenProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: \._$id),
            innerFieldPath: self._childrenForeignKey(relation, Model()),
            negated: true,
            closure: closure
        )
        self.query.filters.append(filter)
        return self
    }

    /// Filters the query using `OR` to exclude models that have related child models matching
    /// the given conditions.
    ///
    /// This is the `OR` variant of ``whereDoesntHave(_:_:)``.
    ///
    /// ```swift
    /// // Get all authors who are named "Alice" OR have no published posts
    /// Author.query(on: db)
    ///     .filter(\.$name == "Alice")
    ///     .orWhereDoesntHave(\.$posts) { post in
    ///         post.filter(\.$status == "published")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - relation: A key path to a `@Children` relationship on the model.
    ///   - closure: An optional closure that configures the query on the related model.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func orWhereDoesntHave<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ChildrenProperty<Model, Related>>,
        _ closure: (QueryBuilder<Related>) -> QueryBuilder<Related> = { $0 }
    ) -> Self {
        let filter = self._buildWhereExistsFilter(
            outerFieldPath: Model.path(for: \._$id),
            innerFieldPath: self._childrenForeignKey(relation, Model()),
            negated: true,
            closure: closure
        )
        return self._addOrFilter(filter)
    }

    /// Resolves the foreign key column on the child table that references the parent.
    ///
    /// A `@Children(for: \.$author)` relationship means the child model (`Post`) has a `@Parent`
    /// property pointing back to the parent. This helper walks the `RelationParentKey` to find the
    /// actual database column name (e.g. `"author_id"`).
    ///
    /// - Parameters:
    ///   - relation: The key path to the `@Children` property.
    ///   - model: An instance of the parent model used to access the property wrapper.
    /// - Returns: The field path of the foreign key on the child table.
    private func _childrenForeignKey<Related: FluentKit.Model>(
        _ relation: KeyPath<Model, ChildrenProperty<Model, Related>>,
        _ model: Model
    ) -> [FieldKey] {
        let children = model[keyPath: relation]
        switch children.parentKey {
        case .required(let keypath):
            return Related.path(for: keypath.appending(path: \.$id))
        case .optional(let keypath):
            return Related.path(for: keypath.appending(path: \.$id))
        }
    }
}