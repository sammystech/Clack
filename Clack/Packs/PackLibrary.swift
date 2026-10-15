import Foundation
import Observation
import os

/// The list of available packs (built-in + custom), the folders they come from,
/// and the packs that couldn't be loaded. Scanning and decoding run off the main actor.
@MainActor @Observable final class PackLibrary {
    private(set) var builtIn: [PackDescriptor]
    private(set) var custom: [PackDescriptor] = []
    var all: [PackDescriptor] { builtIn + custom }
    private(set) var failures: [PackLoadFailure] = []
    private(set) var folders: [PackFolder] = []
    private(set) var isScanning = false
    private(set) var hasScannedOnce = false
    let managedFolder: URL

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var index: [String: PackDescriptor] = [:]
    @ObservationIgnored private var scanFailures: [PackLoadFailure] = []
    @ObservationIgnored private var loadFailures: [String: PackLoadFailure] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanPending = false
    @ObservationIgnored private var didPruneCache = false
    @ObservationIgnored private var isWatching = false
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var watchedPaths: [String] = []

    init(preferences: Preferences) {
        self.preferences = preferences
        self.managedFolder = PackPaths.managedFolder
        try? FileManager.default.createDirectory(at: managedFolder, withIntermediateDirectories: true)
        self.builtIn = Self.builtInDescriptors()
        self.folders = Self.computeFolders(managed: managedFolder, userPaths: preferences.customPackFolders)
        rebuildIndex()
    }

    // MARK: - Scanning

    func rescan() async {
        if let running = scanTask {
            rescanPending = true
            await running.value
            return
        }
        isScanning = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.rescanPending = false
                await self.performScan()
            } while self.rescanPending
        }
        scanTask = task
        await task.value
        scanTask = nil
        isScanning = false
    }

    private func performScan() async {
        let folders = Self.computeFolders(managed: managedFolder, userPaths: preferences.customPackFolders)
        if folders != self.folders { self.folders = folders }
        let prune = !didPruneCache
        didPruneCache = true

        let result = await Task.detached(priority: .userInitiated) {
            await PackScanner.scan(folders: folders, pruneCache: prune)
        }.value

        builtIn = Self.builtInDescriptors()
        custom = result.descriptors
        scanFailures = result.failures
        let liveIDs = Set(custom.map(\.id))
        loadFailures = loadFailures.filter { liveIDs.contains($0.key) || $0.key.hasPrefix("builtin.") }
        publishFailures()
        rebuildIndex()
        hasScannedOnce = true
        updateWatcher()
        Log.packs.info("Scan finished: \(result.descriptors.count, privacy: .public) custom packs, \(result.failures.count, privacy: .public) failures")
    }

    func descriptor(id: String) -> PackDescriptor? { index[id] }

    func randomPackID(excluding excluded: String) -> String? {
        let candidates = all.map(\.id).filter { $0 != excluded }
        return candidates.randomElement()
    }

    // MARK: - Loading

    func loadBank(for d: PackDescriptor) async throws -> any SoundBank {
        switch d.source {
        case .builtIn:
            let bank = try await BuiltInPacks.makeBank(id: d.id)
            clearLoadFailure(d.id)
            return bank
        case .custom:
            let bank = try await Task.detached(priority: .userInitiated) {
                try await MechvibesPackLoader.load(d)
            }.value
            clearLoadFailure(d.id)
            return bank
        }
    }

    func recordLoadFailure(packID: String, reason: String) {
        let d = index[packID]
        let url = d?.folderURL ?? (packID.hasPrefix("custom:")
            ? URL(fileURLWithPath: String(packID.dropFirst("custom:".count)))
            : managedFolder)
        let folderName = d?.folderURL?.lastPathComponent ?? d?.name ?? url.lastPathComponent
        loadFailures[packID] = PackLoadFailure(id: packID, folderName: folderName, url: url, reason: reason)
        publishFailures()
    }

    private func clearLoadFailure(_ id: String) {
        guard loadFailures.removeValue(forKey: id) != nil else { return }
        publishFailures()
    }

    private func publishFailures() {
        var merged = scanFailures
        let scanIDs = Set(merged.map(\.id))
        let recorded = loadFailures.values
            .filter { !scanIDs.contains($0.id) }
            .sorted { $0.folderName.localizedStandardCompare($1.folderName) == .orderedAscending }
        merged.append(contentsOf: recorded)
        if merged != failures { failures = merged }
    }

    // MARK: - Import

    func importPack(from url: URL) async throws -> PackDescriptor {
        let managed = managedFolder
        let destination = try await Task.detached(priority: .userInitiated) {
            try await PackImporter.importPack(from: url, into: managed)
        }.value
        await rescan()
        let target = PackPaths.realPath(destination)
        guard let d = custom.first(where: { $0.folderURL.map(PackPaths.realPath) == target }) else {
            throw PackError.notAPack
        }
        return d
    }

    // MARK: - Watching

    func startWatching() {
        isWatching = true
        updateWatcher(force: true)
    }

    private func updateWatcher(force: Bool = false) {
        guard isWatching else { return }
        let paths = folders.filter(\.exists).map { $0.url.path }
        guard force || paths != watchedPaths || watcher == nil else { return }
        watcher?.stop()
        watchedPaths = paths
        watcher = paths.isEmpty ? nil : FolderWatcher(paths: folders.filter(\.exists).map(\.url), latency: 0.5) { [weak self] in
            guard let self else { return }
            Task { await self.rescan() }
        }
    }

    // MARK: - Helpers

    private func rebuildIndex() {
        var map: [String: PackDescriptor] = [:]
        for d in builtIn + custom where map[d.id] == nil { map[d.id] = d }
        index = map
    }

    private static func builtInDescriptors() -> [PackDescriptor] {
        BuiltInPacks.catalog.map {
            PackDescriptor(id: $0.id, name: $0.name, source: .builtIn,
                           folderURL: nil, configURL: nil, hasKeyUpSounds: true)
        }
    }

    private static func computeFolders(managed: URL, userPaths: [String]) -> [PackFolder] {
        var result: [PackFolder] = []
        var seen = Set<String>()

        func add(_ url: URL, _ kind: PackFolder.Kind, onlyIfExists: Bool) {
            let standardized = url.standardizedFileURL
            let exists = PackPaths.isDirectory(standardized)
            if onlyIfExists && !exists { return }
            let key = PackPaths.realPath(standardized)
            guard seen.insert(key).inserted else { return }
            result.append(PackFolder(id: standardized.path, url: standardized, kind: kind, exists: exists))
        }

        if let bundled = PackPaths.bundledFolder { add(bundled, .bundled, onlyIfExists: true) }
        add(managed, .managed, onlyIfExists: false)
        add(PackPaths.mechvibesCustom, .mechvibes, onlyIfExists: true)
        add(PackPaths.mechvibesV2Custom, .mechvibesV2, onlyIfExists: true)
        for path in userPaths {
            let expanded = (path as NSString).expandingTildeInPath
            guard !expanded.isEmpty else { continue }
            add(URL(fileURLWithPath: expanded, isDirectory: true), .user, onlyIfExists: false)
        }
        return result
    }
}

// MARK: - Scanner (off the main actor)

nonisolated enum PackScanner {
    struct Result: Sendable {
        var descriptors: [PackDescriptor]
        var failures: [PackLoadFailure]
    }

    private static let cacheMaxAge: TimeInterval = 30 * 24 * 60 * 60

    static func scan(folders: [PackFolder], pruneCache: Bool) async -> Result {
        if pruneCache { pruneOldCaches() }

        var found: [(descriptor: PackDescriptor, folderName: String)] = []
        var failures: [PackLoadFailure] = []
        var seenPacks = Set<String>()
        var seenFailures = Set<String>()

        for folder in folders where folder.exists {
            for entry in PackPaths.visibleContents(of: folder.url) {
                if Task.isCancelled { break }
                let isDir = PackPaths.isDirectory(entry)
                let isZip = !isDir && entry.pathExtension.lowercased() == "zip"
                guard isDir || isZip else { continue }

                let entryName = entry.lastPathComponent
                let configURL: URL?
                if isZip {
                    let dest = PackPaths.zipCache.appendingPathComponent(
                        PackPaths.cacheKey(for: entry, prefix: 16), isDirectory: true)
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        do {
                            try await PackPaths.unzip(entry, to: dest)
                        } catch {
                            recordFailure(entry, error, into: &failures, seen: &seenFailures)
                            continue
                        }
                    }
                    configURL = PackPaths.findConfig(in: dest, maxDepth: 3)
                    if configURL == nil {
                        recordFailure(entry, PackError.noConfig, into: &failures, seen: &seenFailures)
                        continue
                    }
                } else {
                    // A subfolder without a config.json is not a pack; skip it quietly.
                    configURL = PackPaths.findConfig(in: entry, maxDepth: 2)
                }
                guard let configURL else { continue }

                let packFolder = configURL.deletingLastPathComponent()
                let identity = isZip ? entry : packFolder
                guard seenPacks.insert(PackPaths.realPath(identity)).inserted else { continue }

                do {
                    let config = try MechvibesConfig.load(configURL: configURL)
                    let fallbackName = isZip ? entry.deletingPathExtension().lastPathComponent : packFolder.lastPathComponent
                    let trimmed = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let descriptor = PackDescriptor(
                        id: "custom:" + identity.standardizedFileURL.path,
                        name: trimmed.isEmpty ? fallbackName : trimmed,
                        source: .custom,
                        folderURL: packFolder.standardizedFileURL,
                        configURL: configURL.standardizedFileURL,
                        hasKeyUpSounds: config.hasKeyUp)
                    found.append((descriptor, isZip ? entryName : packFolder.lastPathComponent))
                } catch {
                    recordFailure(isZip ? entry : packFolder, error, into: &failures, seen: &seenFailures)
                }
            }
        }

        return Result(descriptors: disambiguate(found), failures: failures)
    }

    private static func recordFailure(_ url: URL, _ error: any Error,
                                      into failures: inout [PackLoadFailure], seen: inout Set<String>) {
        let standardized = url.standardizedFileURL
        guard seen.insert(PackPaths.realPath(standardized)).inserted else { return }
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        failures.append(PackLoadFailure(
            id: "custom:" + standardized.path,
            folderName: standardized.lastPathComponent,
            url: standardized,
            reason: reason))
        Log.packs.notice("A pack couldn't be listed: \(reason, privacy: .public)")
    }

    /// Sorts by name and appends " (<folder>)" to every name that collides.
    private static func disambiguate(_ found: [(descriptor: PackDescriptor, folderName: String)]) -> [PackDescriptor] {
        var counts: [String: Int] = [:]
        for item in found { counts[item.descriptor.name.lowercased(), default: 0] += 1 }
        let named = found.map { item -> PackDescriptor in
            let d = item.descriptor
            guard counts[d.name.lowercased(), default: 0] > 1 else { return d }
            return PackDescriptor(id: d.id, name: "\(d.name) (\(item.folderName))", source: d.source,
                                  folderURL: d.folderURL, configURL: d.configURL, hasKeyUpSounds: d.hasKeyUpSounds)
        }
        return named.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Removes cache entries older than 30 days from Decoded/ and Zips/.
    private static func pruneOldCaches() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-cacheMaxAge)
        for dir in [PackPaths.decodedCache, PackPaths.zipCache] {
            guard let items = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { continue }
            for item in items {
                let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified < cutoff {
                    try? fm.removeItem(at: item)
                }
            }
        }
    }
}
