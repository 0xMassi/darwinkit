import Foundation

/// Protocol for iCloud file operations and monitoring.
public protocol CloudProvider {
    func containerURL() -> URL?
    func isAvailable() -> Bool
    func coordinatedRead(at url: URL) throws -> Data
    func coordinatedWrite(_ data: Data, to url: URL) throws
    func coordinatedDelete(at url: URL) throws
    func coordinatedMove(from source: URL, to destination: URL) throws
    func coordinatedCopy(from source: URL, to destination: URL) throws
    func ensureDirectory(at url: URL) throws
    func listDirectory(at url: URL) throws -> [DirectoryEntry]
    func startMonitoring(callback: @escaping ([String]) -> Void)
    func stopMonitoring()
}

public struct DirectoryEntry {
    public let name: String
    public let isDirectory: Bool
    public let size: Int
    public let modified: Date?

    public init(name: String, isDirectory: Bool, size: Int, modified: Date?) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
    }
}

/// iCloud file operations via NSFileCoordinator + NSMetadataQuery monitoring.
/// Mirrors the iOS CloudContainer.swift patterns for cross-device consistency.
public final class AppleCloudProvider: NSObject, CloudProvider {
    private let containerIdentifier = "iCloud.com.0xmassi.stik"
    private var metadataQuery: NSMetadataQuery?
    private var metadataObserver: NSObjectProtocol?
    private var changeCallback: (([String]) -> Void)?
    private var debounceWorkItem: DispatchWorkItem?

    /// Cached container URL — resolved once, reused thereafter
    private var resolvedContainerURL: URL?
    private var containerResolved = false

    public override init() {
        super.init()
    }

    // MARK: - Container Resolution

    public func containerURL() -> URL? {
        if containerResolved { return resolvedContainerURL }
        containerResolved = true
        resolvedContainerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: containerIdentifier
        )
        return resolvedContainerURL
    }

    public func isAvailable() -> Bool {
        containerURL() != nil
    }

    /// The Documents/Stik directory inside the iCloud container
    public func stikRoot() -> URL? {
        guard let container = containerURL() else { return nil }
        return container.appendingPathComponent("Documents/Stik")
    }

    // MARK: - Coordinated File Operations

    public func coordinatedRead(at url: URL) throws -> Data {
        var data = Data()
        var coordinatorError: NSError?
        var readError: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordURL in
            do { data = try Data(contentsOf: coordURL) }
            catch { readError = error }
        }

        if let coordinatorError { throw coordinatorError }
        if let readError { throw readError }
        return data
    }

    public func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordURL in
            do { try data.write(to: coordURL, options: .atomic) }
            catch { writeError = error }
        }

        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    public func coordinatedDelete(at url: URL) throws {
        var coordinatorError: NSError?
        var deleteError: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinatorError) { coordURL in
            do { try FileManager.default.removeItem(at: coordURL) }
            catch { deleteError = error }
        }

        if let coordinatorError { throw coordinatorError }
        if let deleteError { throw deleteError }
    }

    public func coordinatedMove(from source: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator()

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        coordinator.coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinatorError
        ) { srcURL, dstURL in
            do { try FileManager.default.moveItem(at: srcURL, to: dstURL) }
            catch { moveError = error }
        }

        if let coordinatorError { throw coordinatorError }
        if let moveError { throw moveError }
    }

    public func coordinatedCopy(from source: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        coordinator.coordinate(
            readingItemAt: source, options: [],
            writingItemAt: destination, options: .forReplacing,
            error: &coordinatorError
        ) { srcURL, dstURL in
            do {
                if FileManager.default.fileExists(atPath: dstURL.path) {
                    try FileManager.default.removeItem(at: dstURL)
                }
                try FileManager.default.copyItem(at: srcURL, to: dstURL)
            }
            catch { copyError = error }
        }

        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
    }

    public func ensureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func listDirectory(at url: URL) throws -> [DirectoryEntry] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents.compactMap { itemURL in
            let values = try? itemURL.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
            ])
            return DirectoryEntry(
                name: itemURL.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                size: values?.fileSize ?? 0,
                modified: values?.contentModificationDate
            )
        }
    }

    // MARK: - NSMetadataQuery Monitoring

    public func startMonitoring(callback: @escaping ([String]) -> Void) {
        stopMonitoring()
        self.changeCallback = callback

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemFSNameKey)

        metadataObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] notification in
            self?.handleMetadataUpdate(notification)
        }

        query.start()
        metadataQuery = query
        log("iCloud monitoring started")
    }

    public func stopMonitoring() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        metadataQuery?.stop()
        metadataQuery = nil
        if let observer = metadataObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        metadataObserver = nil
        changeCallback = nil
        log("iCloud monitoring stopped")
    }

    /// Extract changed file paths from NSMetadataQuery update notification.
    /// Debounces with 2s delay to avoid flooding Rust with individual file changes.
    private func handleMetadataUpdate(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }

        var changedPaths: [String] = []

        // Collect paths from added/changed items
        if let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] {
            for item in added {
                if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                    changedPaths.append(path)
                }
            }
        }
        if let changed = notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] {
            for item in changed {
                if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                    changedPaths.append(path)
                }
            }
        }
        if let removed = notification.userInfo?[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem] {
            for item in removed {
                if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                    changedPaths.append(path)
                }
            }
        }

        // If no specific changes in userInfo, do a full scan
        if changedPaths.isEmpty {
            query.disableUpdates()
            for i in 0..<query.resultCount {
                if let item = query.result(at: i) as? NSMetadataItem,
                   let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                    changedPaths.append(path)
                }
            }
            query.enableUpdates()
        }

        guard !changedPaths.isEmpty else { return }

        // Debounce: wait 2s after the last change before notifying Rust
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.changeCallback?(changedPaths)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[darwinkit:cloud] \(message)\n".utf8))
    }
}
