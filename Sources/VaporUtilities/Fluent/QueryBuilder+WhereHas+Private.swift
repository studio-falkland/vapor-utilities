import FluentKit
import FluentSQL
import SQLKit

extension QueryBuilder {
    /// Builds a correlated `EXISTS`/`NOT EXISTS` subquery filter.
    ///
    /// This is the shared engine behind all `whereHas`/`whereDoesntHave` variants. It:
    ///
    /// 1. Creates a fresh `QueryBuilder` for the related model and applies the user's filter closure.
    /// 2. Converts that builder's `DatabaseQuery` to a `SQLSelect` using `SQLQueryConverter`.
    /// 3. Sets `SELECT 1` for efficiency (the subquery only needs to check for row existence).
    /// 4. Adds a join condition: `inner_table.inner_field = outer_table.outer_field`.
    ///    This correlates the subquery with the outer query — e.g. `posts.author_id = authors.id`.
    /// 5. Wraps the result in `EXISTS` or `NOT EXISTS`.
    ///
    /// The join condition direction depends on the relationship type:
    /// - `@Children` / `@OptionalChild`: `inner_field` is the child's foreign key, `outer_field` is the parent's ID.
    /// - `@Parent` / `@OptionalParent`: `inner_field` is the related table's ID, `outer_field` is the current model's foreign key.
    ///
    /// - Parameters:
    ///   - outerFieldPath: The field path on the outer (current) query's table.
    ///   - innerFieldPath: The field path on the inner (subquery) table.
    ///   - negated: If `true`, uses `NOT EXISTS` instead of `EXISTS`.
    ///   - closure: A closure that configures the query on the related model.
    /// - Returns: A `DatabaseQuery.Filter` containing the EXISTS/NOT EXISTS SQL expression.
    func _buildWhereExistsFilter<Related: FluentKit.Model>(
        outerFieldPath: [FieldKey],
        innerFieldPath: [FieldKey],
        negated: Bool,
        closure: (QueryBuilder<Related>) -> QueryBuilder<Related>
    ) -> DatabaseQuery.Filter {
        let outerSchema = Model.schemaOrAlias
        let outerSpace = Model.spaceIfNotAliased
        let innerSchema = Related.schemaOrAlias
        let innerSpace = Related.spaceIfNotAliased

        // Step 1: Build the child query with the user's filters.
        let childBuilder = Related.query(on: self.database)
        let filteredBuilder = closure(childBuilder)

        // Step 2: Convert the child query to a SQL select.
        var childQuery = filteredBuilder.query
        childQuery.action = .read
        // Clear limits/offsets — we only care about existence, not pagination.
        childQuery.limits = []
        childQuery.offsets = []

        let converter = SQLQueryConverter(delegate: WhereHasSQLConverterDelegate())
        guard var select = converter.convert(childQuery) as? SQLSelect else {
            // If conversion fails (e.g. non-SQL database), return a no-op filter.
            return .group([], .and)
        }

        // Step 3: Use SELECT 1 — we only need to check for row existence.
        select.columns = [SQLLiteral.numeric("1")]

        // Step 4: Build the correlated join condition.
        // This creates: inner_table.inner_field = outer_table.outer_field
        // e.g.: "posts"."author_id" = "authors"."id"
        let outerTable = QualifiedTable(outerSchema, space: outerSpace)
        let innerTable = QualifiedTable(innerSchema, space: innerSpace)

        let joinCondition = SQLBinaryExpression(
            left: SQLColumn(
                SQLIdentifier(innerFieldPath[0].description),
                table: innerTable
            ),
            op: SQLBinaryOperator.equal,
            right: SQLColumn(
                SQLIdentifier(outerFieldPath[0].description),
                table: outerTable
            )
        )

        // Combine with the user's filter predicate (if any).
        if let existingPredicate = select.predicate {
            select.predicate = SQLBinaryExpression(
                left: joinCondition,
                op: SQLBinaryOperator.and,
                right: existingPredicate
            )
        } else {
            select.predicate = joinCondition
        }

        // Step 5: Wrap in EXISTS/NOT EXISTS and return as a custom filter.
        let exists = SQLExists(subquery: select, negated: negated)
        return .sql(exists)
    }

    /// Adds a filter using OR semantics, wrapping it with existing filters as needed.
    ///
    /// This ensures `orWhereHas`/`orWhereDoesntHave` produce correct SQL like:
    /// ```sql
    /// WHERE (existing_filter AND ...) OR new_filter
    /// ```
    ///
    /// The logic handles three cases:
    /// - **No existing filters**: The filter is added directly. OR is a no-op.
    /// - **Already an OR group**: The new filter is appended to the existing group to avoid
    ///   unnecessary nesting. This keeps chained `orWhereHas` calls flat.
    /// - **Otherwise**: All existing filters are wrapped in an `.and` group, then combined
    ///   with the new filter in an `.or` group.
    ///
    /// - Parameter filter: The filter to add with OR semantics.
    /// - Returns: `self` for chaining.
    @discardableResult
    func _addOrFilter(_ filter: DatabaseQuery.Filter) -> Self {
        if self.query.filters.isEmpty {
            // No existing filters — OR is a no-op, just add directly.
            self.query.filters.append(filter)
        } else if self.query.filters.count == 1,
                  case .group(let subFilters, .or) = self.query.filters[0] {
            // Already an OR group — append to it to avoid nesting.
            // e.g. .orWhereHas(A).orWhereHas(B) stays as one OR group, not nested.
            var newFilters = subFilters
            newFilters.append(filter)
            self.query.filters = [.group(newFilters, .or)]
        } else {
            // Wrap existing filters in an AND group, then OR with the new filter.
            // e.g. .filter(X).orWhereHas(Y) → WHERE (X) OR EXISTS (Y)
            let existingGroup = DatabaseQuery.Filter.group(self.query.filters, .and)
            self.query.filters = [.group([existingGroup, filter], .or)]
        }
        return self
    }
}