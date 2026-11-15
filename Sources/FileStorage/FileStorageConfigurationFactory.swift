import Logging
import Vapor

/// Constructs and configures a ``FileStorageDriver``.
///
/// Factories are registered with `fileStorages.use(...)` and are only invoked
/// the first time a driver is requested. This lets a factory use the
/// application logger without requiring an `Application` reference.
public struct FileStorageConfigurationFactory: Sendable {
    /// Creates and returns a configured driver.
    let make: @Sendable (Logger) throws -> any FileStorageDriver

    /// Creates a new factory.
    ///
    /// - Parameter make: A closure that constructs the driver. It is called at
    ///   most once per application, on first access.
    public init(make: @escaping @Sendable (Logger) throws -> any FileStorageDriver) {
        self.make = make
    }
}
