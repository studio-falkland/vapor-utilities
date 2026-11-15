import Foundation
import Logging
import ServiceLifecycle
import Synchronization
import Vapor

/// Identifies a named ``FileStorageDriver`` registered on the application.
public struct FileStorageID: Hashable, Sendable {
    /// The default storage driver.
    public static let `default` = FileStorageID(string: "default")

    /// The unique name of the driver.
    public let string: String

    /// Creates a new identifier.
    public init(string: String) {
        self.string = string
    }
}

/// The registry of file storage drivers for an application.
///
/// Create one in `configure`, register it with the application lifecycle, and
/// pass it to the controllers that need it:
///
/// ```swift
/// let fileStorages = FileStorages()
/// fileStorages.use(.s3(.init(
///     bucket: "acme-uploads",
///     region: .euCentral1,
///     accessKeyId: "...",
///     secretAccessKey: "..."
/// )))
/// app.addService(fileStorages)
/// try await routes(app, fileStorages: fileStorages)
/// ```
public final class FileStorages: Sendable, Service {
    /// The state shared by concurrent calls.
    private struct State: Sendable {
        /// Configuration factories, keyed by identifier.
        var factories: [FileStorageID: FileStorageConfigurationFactory] = [:]

        /// Lazily constructed drivers, keyed by identifier.
        var drivers: [FileStorageID: any FileStorageDriver] = [:]

        /// Whether ``shutdown()`` has run.
        var isShutdown = false
    }

    /// The registry state.
    private let state = Mutex(State())

    /// The logger used for driver construction and shutdown.
    private let logger: Logger

    /// Creates a new registry.
    ///
    /// - Parameter logger: The logger used for driver diagnostics.
    public init(logger: Logger = Logger.current) {
        self.logger = logger
    }

    /// Registers a driver factory, optionally under a named identifier.
    ///
    /// - Parameters:
    ///   - factory: The factory that constructs the driver.
    ///   - id: The identifier to register the driver under. Defaults to
    ///     the default driver.
    public func use(_ factory: FileStorageConfigurationFactory, as id: FileStorageID = .default) {
        self.state.withLock { $0.factories[id] = factory }
    }

    /// Returns the driver registered for `id`, constructing it on first access.
    ///
    /// - Parameter id: The identifier of the driver to return.
    /// - Returns: The configured driver.
    public func require(_ id: FileStorageID = .default) -> any FileStorageDriver {
        self.state.withLock { state in
            // Reuse an existing driver.
            if let driver = state.drivers[id] {
                return driver
            }

            // Construct the driver from its factory.
            guard let factory = state.factories[id] else {
                fatalError(
                    "FileStorage '\(id.string)' not configured. "
                        + "Use `fileStorages.use(...)` before accessing it."
                )
            }

            let driver: any FileStorageDriver
            do {
                driver = try factory.make(self.logger)
            } catch {
                fatalError("Failed to construct FileStorage driver '\(id.string)': \(error)")
            }
            state.drivers[id] = driver
            return driver
        }
    }

    /// Waits for shutdown, then releases the drivers.
    public func run() async throws {
        try? await gracefulShutdown()
        await self.shutdown()
    }

    /// Releases every constructed driver.
    public func shutdown() async {
        // Take the drivers and mark the registry as shut down.
        let drivers = self.state.withLock { state -> [any FileStorageDriver] in
            defer {
                state.drivers.removeAll()
                state.isShutdown = true
            }
            return Array(state.drivers.values)
        }

        // Shut down each driver, logging failures.
        for driver in drivers {
            do {
                try await driver.shutdown()
            } catch {
                self.logger.error("Failed to shut down FileStorage driver: \(error)")
            }
        }
    }
}
