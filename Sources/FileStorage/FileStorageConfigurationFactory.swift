import Vapor

/// Constructs and configures a ``FileStorageDriver`` for a Vapor application.
///
/// Factories are registered with `app.fileStorages.use(...)` and are only
/// invoked the first time a driver is requested. This allows factories to
/// access application resources such as the shared HTTP client.
public struct FileStorageConfigurationFactory: Sendable {
    /// Creates and returns a configured driver for the given application.
    let make: @Sendable (Application) throws -> any FileStorageDriver

    /// Creates a new factory.
    ///
    /// - Parameter make: A closure that constructs the driver. It is called at
    ///   most once per application, on first access.
    public init(make: @escaping @Sendable (Application) throws -> any FileStorageDriver) {
        self.make = make
    }
}