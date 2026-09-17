import FluentKit
import Vapor

/// Type-erased view of a ``FillableField``, so ``FillableDTO`` can enumerate
/// fields via reflection without knowing their static types.
public protocol AnyFillableField {
    /// Whether the decoded request body explicitly contained this field
    /// (a `null` value counts as present).
    var isPresent: Bool { get }
    /// Whether the field is guarded — decoded and validated, but not
    /// auto-applied. Guarded fields are assigned by hand, typically via
    /// ``FillableDTO/willApply(to:on:)`` and `Model.set(_:to:)`.
    var isGuarded: Bool { get }
    /// The database field key this field maps to.
    var fieldKey: FieldKey { get }

    func decode(from decoder: any Decoder) throws
    func encode(to encoder: any Encoder) throws
    func apply(to model: any FluentKit.Fields) throws
}

/// A single fillable field of a ``FillableDTO``.
///
/// The wrapped value is a double optional: `.none` means the key was absent
/// from the request body, `.some(nil)` means it was explicitly set to `null`,
/// and `.some(.some(value))` means a value was provided. This is what allows
/// patches to leave keys untouched, null out optional columns, or write values.
///
/// > This is a `final class` (like FluentKit's own property wrappers) so that
/// > reflection-based decoding mutates the stored instance rather than a copy.
///
/// ```swift
/// final class TodoPatch: FillableDTO<Todo> {
///     @FillableField(\Todo.$title) var title: String??      // required column
///     @FillableField(\Todo.$note) var note: String???       // nullable column
///     @FillableField(\Todo.$startsAt, converting: TodoPatch.parseDate) var startsAt: String??
///     @FillableField(\Todo.$ownerID, guarded: true) var ownerID: UUID???
/// }
/// ```
@propertyWrapper
public final class FillableField<Model, Patched, Property>: @unchecked Sendable
    where Model: FluentKit.Model, Patched: Codable & Sendable, Property: QueryableProperty, Property.Model == Model
{
    // The triple state of the field: `.none` = key absent from the body,
    // `.some(nil)` = explicitly null, `.some(.some(v))` = a value.
    public var wrappedValue: Patched??

    // The typed key path is the whole trick: `model[keyPath:].value = ...`
    // is a compile-time-checked assignment that Fluent records as "changed",
    // so the value will be written by the next `save()`.
    private let keyPath: KeyPath<Model, Property>

    // Optional conversion from the DTO type to the column type
    // (e.g. an ISO-8601 `String` into a `Date` column). Identity by default.
    private let convert: (Patched) throws -> Property.Value

    // Guarded fields are decoded and validated but never auto-applied;
    // the DTO subclass assigns them itself, usually from willApply(to:on:).
    public let isGuarded: Bool

    // Identity by default: `{ $0 as! Property.Value }` is a no-op cast both for
    // required columns (String → String) and nullable ones (String → String?), so
    // the DTO always declares `V??` — the wire type plus "present or not". Whether
    // null is legal is decided at apply time from the column, not the DTO type.
    public init(
        wrappedValue: Patched?? = nil,
        _ keyPath: KeyPath<Model, Property>,
        guarded: Bool = false,
        converting: @escaping (Patched) throws -> Property.Value = { $0 as! Property.Value }
    ) {
        self.wrappedValue = wrappedValue
        self.keyPath = keyPath
        self.isGuarded = guarded
        self.convert = converting
    }
}

extension FillableField: AnyFillableField {
    // "Present" includes explicit nulls: an outer `.some` means the key
    // appeared in the body, whatever its value.
    public var isPresent: Bool {
        self.wrappedValue != nil
    }

    // The database column key, derivable from the key path alone.
    // Used for the identifier guard and for error messages.
    public var fieldKey: FieldKey {
        Model.init()[keyPath: self.keyPath].path[0]
    }

    // Called by FillableDTO only for keys that are present in the body.
    // A JSON null becomes `.some(nil)`; anything else decodes as `Patched`.
    public func decode(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.wrappedValue = .some(nil)
        } else {
            self.wrappedValue = try .some(.some(container.decode(Patched.self)))
        }
    }

    // Encoding mirrors decoding and only ever emits fields that are present.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let present = self.wrappedValue {
            if let value = present {
                try container.encode(value)
            } else {
                try container.encodeNil()
            }
        }
    }

    // The actual assignment: absent values are left untouched, present
    // values are converted and written to the model's input state.
    public func apply(to fields: any FluentKit.Fields) throws {
        guard let model = fields as? Model else { return }

        // Absent → no-op. This is what makes patch requests safe: keys that
        // weren't in the body never reach the model.
        guard let present = self.wrappedValue else { return }

        if let value = present {
            // A real value: convert (identity for already-matching types)
            // and record it as a pending change on the model instance.
            model[keyPath: self.keyPath].value = try self.convert(value)
        } else if Property.Value.self is any FluentKit.AnyOptionalType.Type {
            // The column is nullable: an explicit null maps to SQL NULL.
            let nilValue = (Property.Value.self as! any FluentKit.AnyOptionalType.Type).nil as! Property.Value
            model[keyPath: self.keyPath].value = .some(nilValue)
        } else {
            // The column is required: nulling it is a client error.
            throw Abort(.badRequest, reason: "Cannot set '\(self.fieldKey.description)' to null because it is not optional.")
        }
    }
}