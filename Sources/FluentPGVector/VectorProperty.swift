import FluentKit
import Pgvector

extension Fields {
    /// A Fluent property wrapper for pgvector `vector` columns.
    ///
    /// Stores `[Double]?` values. The `dimensions` parameter is required for
    /// schema generation but is not enforced at the property level.
    ///
    /// ```swift
    /// final class PageChunk: Model {
    ///     @Vector(key: "embedding", dimensions: 2560)
    ///     var embedding: [Double]?
    /// }
    /// ```
    ///
    /// > Important: Before using this property in regular queries (e.g. `Model.query(on: db).all()`),
    /// > call ``FPGVector/registerVectorTypes(on:)`` once during app startup.
    /// > ``QueryBuilder/allWithDistance(_:to:limit:)`` handles this automatically.
    public typealias Vector = VectorProperty<Self>
}

/// A Fluent ``Property``-conforming property wrapper for pgvector `vector` columns.
///
/// This wrapper stores `[Double]?` values, tracks its ``FieldKey`` and ``dimensions``,
/// and emits `vector(dimensions)` as the SQL column type for migrations.
///
/// It is analogous to ``OptionalFieldProperty`` but specialized for vector data.
@propertyWrapper
public final class VectorProperty<Model>: @unchecked Sendable
    where Model: FluentKit.Fields
{
    /// The number of dimensions of the vector.
    public let dimensions: Int

    /// The field key used to map this property to a database column.
    public let key: FieldKey

    /// The value as read from the database output.
    var outputValue: [Double]??

    /// The value as set by the user (pending input).
    var inputValue: DatabaseQuery.Value?

    /// The projected value provides access to the property wrapper itself.
    public var projectedValue: VectorProperty<Model> {
        self
    }

    /// The wrapped value, an optional array of doubles.
    public var wrappedValue: [Double]? {
        get { self.value ?? nil }
        set { self.value = .some(newValue) }
    }

    /// Creates a new vector property.
    ///
    /// - Parameters:
    ///   - key: The field key for the database column.
    ///   - dimensions: The number of dimensions of the vector.
    public init(key: FieldKey, dimensions: Int) {
        self.key = key
        self.dimensions = dimensions
    }
}

// MARK: Property

extension VectorProperty: AnyProperty {}

extension VectorProperty: Property {
    public var value: [Double]?? {
        get {
            if let value = self.inputValue {
                switch value {
                case .bind(let bind):
                    .some(bind as? [Double])
                case .default:
                    fatalError("Cannot access default field for '\(Model.self).\(key)' before it is initialized or fetched")
                case .null:
                    .some(.none)
                default:
                    fatalError("Unexpected input value type for '\(Model.self).\(key)': \(value)")
                }
            } else if let value = self.outputValue {
                .some(value)
            } else {
                .none
            }
        }
        set {
            if let value = newValue {
                self.inputValue = value
                    .flatMap { .bind($0) }
                    ?? .null
            } else {
                self.inputValue = nil
            }
        }
    }
}

// MARK: Queryable

extension VectorProperty: AnyQueryableProperty {
    public var path: [FieldKey] {
        [self.key]
    }
}

extension VectorProperty: QueryableProperty {}

// MARK: Query-addressable

extension VectorProperty: AnyQueryAddressableProperty {
    public var anyQueryableProperty: any AnyQueryableProperty { self }
    public var queryablePath: [FieldKey] { self.path }
}

extension VectorProperty: QueryAddressableProperty {
    public var queryableProperty: VectorProperty<Model> { self }
}

// MARK: Database

extension VectorProperty: AnyDatabaseProperty {
    public var keys: [FieldKey] {
        [self.key]
    }

    public func input(to input: any DatabaseInput) {
        if input.wantsUnmodifiedKeys {
            input.set(self.inputValue ?? self.outputValue.map { $0.map { .bind($0) } ?? .null } ?? .default, at: self.key)
        } else if let inputValue = self.inputValue {
            input.set(inputValue, at: self.key)
        }
    }

    public func output(from output: any DatabaseOutput) throws {
        if output.contains(self.key) {
            self.inputValue = nil
            do {
                if try output.decodeNil(self.key) {
                    self.outputValue = .some(nil)
                } else {
                    // Decode using Pgvector.Vector's PostgresDecodable conformance,
                    // which handles pgvector's binary wire format natively.
                    // PostgresNIO's built-in [Double] decoding expects the standard
                    // PostgreSQL array format and cannot decode pgvector's format.
                    let pgVector = try output.decode(self.key, as: Pgvector.Vector.self)
                    self.outputValue = .some(pgVector.value.map(Double.init))
                }
            } catch {
                throw FluentError.invalidField(
                    name: self.key.description,
                    valueType: [Double].self,
                    error: error
                )
            }
        }
    }
}

// MARK: Codable

extension VectorProperty: AnyCodableProperty {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue)
    }

    public func decode(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = nil
        } else {
            self.value = try container.decode([Double].self)
        }
    }
}

// MARK: - Decodable conformance for Pgvector.Vector

/// Required by ``DatabaseOutput.decode(_:as:)`` which requires ``Decodable``.
/// The ``PostgresDecodable`` fast path in PostgresKit intercepts this at runtime,
/// so this ``Decodable`` implementation is only used as a last resort (e.g. JSON).
extension Pgvector.Vector: @retroactive Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([Float].self))
    }
}

// MARK: CustomStringConvertible

extension VectorProperty: CustomStringConvertible {
    public var description: String {
        "@\(Model.self).Vector(key: \(self.key), dimensions: \(self.dimensions))"
    }
}