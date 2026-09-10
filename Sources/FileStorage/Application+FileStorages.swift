import Dispatch
import NIOConcurrencyHelpers
import Vapor

/// Identifies a named ``FileStorageDriver`` registered on the application.
public struct FileStorageID: Hashable, Sendable {
    /// The default storage driver, accessed via `req.fileStorage`.
    public static let `default` = FileStorageID(string: "default")

    /// The unique name of the driver.
    public let string: String

    /// Creates a new identifier.
    public init(string: String) {
        self.string = string
    }
}

extension Application {
    /// The registry of file storage drivers configured for this application.
    ///
    /// ```swift
    /// app.fileStorages.use(.s3(.init(
    ///     bucket: "acme-uploads",
    ///     region: .eucentral1,
    ///     accessKeyId: "...",
    ///     secretAccessKey: "..."
    /// )))
    /// ```
    public var fileStorages: FileStorages {
        .init(application: self)
    }

    /// The registry of file storage drivers for an application.
    public struct FileStorages: Sendable {
        /// The application this registry belongs to.
        public let application: Application

        /// Configuration factories, keyed by identifier.
        private struct FactoriesKey: StorageKey {
            typealias Value = [FileStorageID: FileStorageConfigurationFactory]
        }

        /// Lazily constructed drivers, keyed by identifier. A lock-protected
        /// box is used so drivers can be added without replacing the value in
        /// application storage (which would discard the shutdown hook).
        private struct DriversKey: StorageKey {
            typealias Value = NIOLockedValueBox<[FileStorageID: any FileStorageDriver]>
        }

        /// Registers a driver factory, optionally under a named identifier.
        ///
        /// - Parameters:
        ///   - factory: The factory that constructs the driver.
        ///   - id: The identifier to register the driver under. Defaults to
        ///     the default driver, accessed via `req.fileStorage`.
        public func use(_ factory: FileStorageConfigurationFactory, as id: FileStorageID = .default) {
            var factories = self.application.storage[FactoriesKey.self] ?? [:]
            factories[id] = factory
            self.application.storage[FactoriesKey.self] = factories
        }

        /// Returns the driver registered for `id`, constructing it on first
        /// access.
        ///
        /// - Precondition: A factory must have been registered for `id` via
        ///   `use(_:as:)` before this is called.
        public func require(_ id: FileStorageID = .default) -> any FileStorageDriver {
            let box: NIOLockedValueBox<[FileStorageID: any FileStorageDriver]>
            if let existing = self.application.storage[DriversKey.self] {
                box = existing
                if let driver = box.withLockedValue({ $0[id] }) {
                    return driver
                }
            } else {
                box = NIOLockedValueBox([:])
                self.application.storage.set(DriversKey.self, to: box) { box in
                    let drivers = box.withLockedValue { $0 }
                    for driver in drivers.values {
                        do {
                            try Self.waitForShutdown(of: driver)
                        } catch {
                            // Vapor logs shutdown failures with the
                            // application logger.
                        }
                    }
                }
            }

            guard let factory = (self.application.storage[FactoriesKey.self] ?? [:])[id] else {
                fatalError(
                    "FileStorage '\(id.string)' not configured. "
                        + "Use `app.fileStorages.use(...)` before accessing `req.fileStorage`."
                )
            }

            let driver: any FileStorageDriver
            do {
                driver = try factory.make(self.application)
            } catch {
                fatalError("Failed to construct FileStorage driver '\(id.string)': \(error)")
            }
            box.withLockedValue { $0[id] = driver }
            return driver
        }

        /// Runs an async driver shutdown to completion from a synchronous
        /// context. `Application.storage` invokes shutdown hooks synchronously,
        /// so this mirrors how Vapor and Soto block on async shutdown.
        private static func waitForShutdown(of driver: any FileStorageDriver) throws {
            let semaphore = DispatchSemaphore(value: 0)
            let errorBox = NIOLockedValueBox<Error?>(nil)
            Task {
                do {
                    try await driver.shutdown()
                } catch {
                    errorBox.withLockedValue { $0 = error }
                }
                semaphore.signal()
            }
            semaphore.wait()
            if let error = errorBox.withLockedValue({ $0 }) {
                throw error
            }
        }
    }
}