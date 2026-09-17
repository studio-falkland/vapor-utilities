import FluentKit
import Vapor

/// Property-wrapper backing storage is reflected with a leading underscore
/// (e.g. `_title`); the JSON key is the Swift property name (`title`).
private func fillableKeyName(_ label: String) -> String {
    label.hasPrefix("_") ? String(label.dropFirst()) : label
}

/// A DTO that mass-assigns decoded request values onto a Fluent model —
/// with `fill` / `update` methods and exact absent/null/value tracking per
/// field.
///
/// Subclass and declare fillable fields:
///
/// ```swift
/// final class TodoPatch: FillableDTO<Todo> {
///     @FillableField(\Todo.$title) var title: String??      // required column
///     @FillableField(\Todo.$note) var note: String??        // nullable column
///
///     override func validate() throws { ... }
///     override func willApply(to todo: Todo, on database: any Database) async throws { ... }
/// }
///
/// // Controller:
/// let patch = try req.content.decode(TodoPatch.self)
/// let todo = try await Todo.findOrFail(req.parameters.get("todoID"), on: req.db)
/// try await todo.update(patch, on: req.db)          // validate → hooks → apply → save
/// // or stage in memory first:
/// try todo.fill(patch)                               // validate + apply, no database
/// ```
open class FillableDTO<Model>: Codable, @unchecked Sendable
    where Model: FluentKit.Model
{
    // The no-arg initializer is required (and called from the decoding init
    // below): every wrapper starts in its "absent" (`.none`) state.
    public required init() {}

    /// Decodes each fillable field that is present in the payload. Absent keys
    /// are left in their initialized (`.none`) state, so "missing" stays
    /// distinct from "explicit null" (`.some(nil)`).
    public required convenience init(from decoder: any Decoder) throws {
        // Plain init first, so the wrappers exist; reflection over the
        // subclass's stored properties then finds every field, including
        // ones declared in the DTO subclass (not in this base class).
        self.init()
        let container = try decoder.container(keyedBy: DynamicKey.self)

        // Mirror yields (label, value) pairs. The label is the Swift property
        // name — our JSON key — and non-fillable helpers are skipped.
        for (label, value) in Mirror(reflecting: self).children {
            guard let label, let field = value as? any AnyFillableField else { continue }

            // `container.contains` is the presence check: absent keys keep
            // their initialized `.none` state instead of being decoded.
            guard let key = DynamicKey(stringValue: fillableKeyName(label)), container.contains(key) else { continue }

            // Hand the raw value container to the wrapper, which knows how
            // to tell null apart from a value for its own type.
            let sub = try container.superDecoder(forKey: key)
            do {
                try field.decode(from: sub)
            } catch {
                // Re-wrap with the field name so decode failures read well
                // in client-facing error messages.
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Could not decode fillable field '\(label)'",
                    underlyingError: error
                ))
            }
        }
    }

    // Encoding mirrors decoding, but only emits fields that are present —
    // an absent field is skipped entirely rather than encoded as null.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (label, value) in Mirror(reflecting: self).children {
            guard let label, let field = value as? any AnyFillableField, field.isPresent else { continue }
            guard let key = DynamicKey(stringValue: fillableKeyName(label)) else { continue }
            try field.encode(to: container.superEncoder(forKey: key))
        }
    }

    /// The database field keys that were present in the decoded payload
    /// (including explicit nulls). Useful for logging or conditional logic.
    public var presentKeys: [FieldKey] {
        // Same reflection walk as decode/encode; only keys whose outer
        // optional is set count as "present".
        Mirror(reflecting: self).children.compactMap { (_, value) in
            guard let field = value as? any AnyFillableField, field.isPresent else { return nil }
            return field.fieldKey
        }
    }

    /// Validates the DTO. Only fields that are present should be validated;
    /// absent keys decode as `nil` (outer optional) and must be ignored.
    open func validate() throws {}

    /// Hook for database-dependent work — uniqueness checks, existence checks,
    /// relation resolution via `set(_:to:)`. Runs after `validate()` and
    /// before values are applied. Only called by ``update(_:on:)``.
    open func willApply(to model: Model, on database: any Database) async throws {}

    /// Applies all unguarded fillable fields to the model. Identifier fields
    /// and nulls targeting required columns are rejected.
    open func apply(to model: Model) throws {
        // Changing the primary key is never a mass-assignment concern, so the
        // model's id keys are collected once and checked per field.
        let idKeys = Set(model._$idKeys)

        // The same reflection walk as decoding, minus guarded fields —
        // guarded fields are the DTO's own responsibility.
        for (_, value) in Mirror(reflecting: self).children {
            guard let field = value as? any AnyFillableField, !field.isGuarded else { continue }
            if idKeys.contains(field.fieldKey) {
                throw Abort(.badRequest, reason: "The model's identifier cannot be mass-assigned.")
            }
            try field.apply(to: model)
        }
    }

    /// `fill`: validate and apply values to the model instance.
    /// Never touches the database, so `willApply` does not run.
    public func fill(_ model: Model) throws {
        // Validate first, so invalid payloads fail before any assignment.
        try self.validate()

        // Assign every present, unguarded field onto the model instance.
        // Fields end up with "input" provenance, so a later `save()` writes
        // exactly the columns that were touched.
        try self.apply(to: model)
    }

    /// `update`: validate, run database hooks, apply values, and
    /// save in one go. Saving is skipped when nothing changed; creating an
    /// empty model is rejected.
    public func update(_ model: Model, on database: any Database) async throws {
        // Same as fill: validate and apply the present fields in memory.
        try self.fill(model)

        // DB-dependent work (uniqueness checks, relation resolution) happens
        // here, where the database is available and before anything is saved.
        try await self.willApply(to: model, on: database)

        // No pending changes? For an existing model that's a clean no-op;
        // for a fresh model it means the body was empty — reject that.
        guard model.hasChanges else {
            if model._$idExists { return }
            throw Abort(.badRequest, reason: "Nothing to create — the body contained no values.")
        }

        // save() routes to update or create depending on the model's id,
        // and runs middleware and timestamp handling like any other save.
        try await model.save(on: database)
    }
}

// MARK: - Model sugar

public extension FluentKit.Model {
    /// Assigns a possibly-absent/null fillable value to a queryable property.
    ///
    /// - `nil` (outer optional): no-op, the property is left untouched.
    /// - `.some(nil)`: writes `NULL` (optional-backed properties only).
    /// - `.some(value)`: writes the value.
    ///
    /// Used by guarded fields, typically from `FillableDTO.willApply(to:on:)`.
    func set<Property: QueryableProperty, Patched: Codable & Sendable>(
        _ value: Patched??,
        to keyPath: KeyPath<Self, Property>,
        converting: @escaping (Patched) throws -> Property.Value = { $0 as! Property.Value }
    ) throws where Property.Model == Self {
        // The outer optional is the presence marker, identical to the DTO
        // semantics: `.none` means "leave it alone".
        guard let present = value else { return }

        // Resolve the property instance on *this* model and guard the id.
        let property = self[keyPath: keyPath]
        let idKeys = Set(Self.init()._$idKeys)
        if idKeys.contains(property.path[0]) {
            throw Abort(.badRequest, reason: "The model's identifier cannot be mass-assigned.")
        }

        if let value = present {
            // A real value — record it as a pending change.
            property.value = try converting(value)
        } else if Property.Value.self is any FluentKit.AnyOptionalType.Type {
            // Explicit null on a nullable column → SQL NULL.
            let nilValue = (Property.Value.self as! any FluentKit.AnyOptionalType.Type).nil as! Property.Value
            property.value = .some(nilValue)
        } else {
            // Explicit null on a required column is a client error.
            throw Abort(.badRequest, reason: "Cannot set '\(property.path[0].description)' to null because it is not optional.")
        }
    }

    /// Convenience for `FillableDTO.fill(_:)`.
    func fill(_ dto: FillableDTO<Self>) throws {
        try dto.fill(self)
    }

    /// Convenience for `FillableDTO.update(_:on:)`.
    func update(_ dto: FillableDTO<Self>, on database: any Database) async throws {
        try await dto.update(self, on: database)
    }
}