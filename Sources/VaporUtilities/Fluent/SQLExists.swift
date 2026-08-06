import FluentKit
import FluentSQL
import SQLKit

// SQLQualifiedTable's canonical location is SQLKit; FluentSQL's re-export is deprecated.
typealias QualifiedTable = SQLKit.SQLQualifiedTable

/// A SQL expression representing an `EXISTS (subquery)` or `NOT EXISTS (subquery)` clause.
///
/// This is a custom `SQLExpression` used internally by the `whereHas`/`whereDoesntHave` family
/// of methods. It wraps a `SQLSelect` subquery and prefixes it with `EXISTS` or `NOT EXISTS`.
///
/// The subquery is wrapped in a `SQLGroupExpression` (parentheses) by the serializer.
///
/// ```sql
/// EXISTS (SELECT 1 FROM "posts" WHERE "posts"."author_id" = "authors"."id")
/// NOT EXISTS (SELECT 1 FROM "posts" WHERE "posts"."author_id" = "authors"."id")
/// ```
struct SQLExists: SQLExpression {
    /// The subquery to wrap with EXISTS.
    let subquery: SQLSelect

    /// If `true`, produces `NOT EXISTS` instead of `EXISTS`.
    let negated: Bool

    init(subquery: SQLSelect, negated: Bool = false) {
        self.subquery = subquery
        self.negated = negated
    }

    func serialize(to serializer: inout SQLSerializer) {
        if self.negated {
            serializer.write("NOT EXISTS ")
        } else {
            serializer.write("EXISTS ")
        }
        // Wrap the subquery in parentheses: EXISTS (SELECT 1 ...)
        SQLGroupExpression(subquery).serialize(to: &serializer)
    }
}

/// A minimal delegate for `SQLQueryConverter` that returns `nil` for all custom data types.
///
/// This is used when converting the child model's `DatabaseQuery` to a `SQLSelect` inside
/// `_buildWhereExistsFilter`. It doesn't need to handle any custom data types since the
/// subquery is only used for existence checking.
struct WhereHasSQLConverterDelegate: SQLConverterDelegate {
    func customDataType(_ dataType: DatabaseSchema.DataType) -> (any SQLExpression)? {
        nil
    }
}