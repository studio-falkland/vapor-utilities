/// A dynamic `CodingKey` used by ``FillableDTO``'s reflection-based decoding.
/// Field names are discovered at runtime via `Mirror`, so coding keys are
/// built from the reflected property names on the fly.
struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}