import Foundation
import SQLite3
import SwiftData

@Model
final class NetworkAnnotation {
    @Attribute(.unique) var bssid: String
    var friendlyName: String
    var isOwned: Bool
    var accentSeed: Double

    init(bssid: String, friendlyName: String, isOwned: Bool, accentSeed: Double) {
        self.bssid = bssid
        self.friendlyName = friendlyName
        self.isOwned = isOwned
        self.accentSeed = accentSeed
    }
}

@MainActor
protocol NetworkAnnotationRepositoryProtocol: AnyObject {
    func loadAll() throws -> [NetworkAnnotationRecord]
    func save(_ record: NetworkAnnotationRecord) throws
}

@MainActor
final class AnnotationRepository: NetworkAnnotationRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func loadAll() throws -> [NetworkAnnotationRecord] {
        let descriptor = FetchDescriptor<NetworkAnnotation>(
            sortBy: [SortDescriptor(\.friendlyName), SortDescriptor(\.bssid)]
        )
        return try context.fetch(descriptor).map {
            NetworkAnnotationRecord(
                bssid: $0.bssid,
                friendlyName: $0.friendlyName,
                isOwned: $0.isOwned,
                accentSeed: $0.accentSeed
            )
        }
    }

    func save(_ record: NetworkAnnotationRecord) throws {
        let bssid = record.bssid
        let descriptor = FetchDescriptor<NetworkAnnotation>(
            predicate: #Predicate { $0.bssid == bssid }
        )
        let existing = try context.fetch(descriptor).first

        let trimmedName = record.trimmedFriendlyName
        if trimmedName.isEmpty, !record.isOwned {
            if let existing {
                context.delete(existing)
            }
            try context.save()
            return
        }

        let model = existing ?? NetworkAnnotation(
            bssid: record.bssid,
            friendlyName: trimmedName,
            isOwned: record.isOwned,
            accentSeed: record.accentSeed
        )

        model.friendlyName = trimmedName
        model.isOwned = record.isOwned
        model.accentSeed = record.accentSeed

        if existing == nil {
            context.insert(model)
        }

        try context.save()
    }
}

@MainActor
final class InMemoryAnnotationRepository: NetworkAnnotationRepositoryProtocol {
    private var records: [String: NetworkAnnotationRecord]

    init(records: [NetworkAnnotationRecord] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.bssid, $0) })
    }

    func loadAll() throws -> [NetworkAnnotationRecord] {
        records.values.sorted {
            ($0.trimmedFriendlyName, $0.bssid) < ($1.trimmedFriendlyName, $1.bssid)
        }
    }

    func save(_ record: NetworkAnnotationRecord) throws {
        if record.trimmedFriendlyName.isEmpty, !record.isOwned {
            records[record.bssid] = nil
        } else {
            records[record.bssid] = NetworkAnnotationRecord(
                bssid: record.bssid,
                friendlyName: record.trimmedFriendlyName,
                isOwned: record.isOwned,
                accentSeed: record.accentSeed
            )
        }
    }
}

enum AnnotationStoreLocation {
    private static let storeDirectoryName = "io.spectrum.app"
    private static let storeFileName = "NetworkAnnotations.store"
    private static let legacyStoreFileName = "default.store"
    private static let compatibilityTableName = "ZNETWORKANNOTATION"
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func makeModelContainer(
        schema: Schema,
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appSupportDirectory: URL? = nil
    ) throws -> ModelContainer {
        let storeURL = try prepareStoreURL(
            fileManager: fileManager,
            bundleIdentifier: bundleIdentifier,
            appSupportDirectory: appSupportDirectory
        )
        let configuration = ModelConfiguration(
            "NetworkAnnotations",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func prepareStoreURL(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appSupportDirectory: URL? = nil
    ) throws -> URL {
        let appSupportURL = try resolveApplicationSupportDirectory(
            fileManager: fileManager,
            appSupportDirectory: appSupportDirectory
        )
        let storeDirectoryURL = appSupportURL
            .appendingPathComponent(bundleIdentifier ?? storeDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)

        let storeURL = storeDirectoryURL.appendingPathComponent(storeFileName, isDirectory: false)
        try migrateLegacyStoreIfNeeded(
            fileManager: fileManager,
            legacyStoreURL: appSupportURL.appendingPathComponent(legacyStoreFileName, isDirectory: false),
            storeURL: storeURL
        )
        return storeURL
    }

    static func migrateLegacyStoreIfNeeded(
        fileManager: FileManager = .default,
        legacyStoreURL: URL,
        storeURL: URL
    ) throws {
        guard !storeArtifactsExist(at: storeURL, fileManager: fileManager) else { return }
        guard storeArtifactsExist(at: legacyStoreURL, fileManager: fileManager) else { return }
        guard legacyStoreContainsNetworkAnnotations(at: legacyStoreURL) else { return }

        for (sourceURL, destinationURL) in artifactPairs(from: legacyStoreURL, to: storeURL) {
            guard fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)) else { continue }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func resolveApplicationSupportDirectory(
        fileManager: FileManager,
        appSupportDirectory: URL?
    ) throws -> URL {
        if let appSupportDirectory {
            return appSupportDirectory
        }

        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return directory
    }

    private static func storeArtifactsExist(at storeURL: URL, fileManager: FileManager) -> Bool {
        artifactURLs(for: storeURL).contains { artifactURL in
            fileManager.fileExists(atPath: artifactURL.path(percentEncoded: false))
        }
    }

    private static func artifactPairs(from legacyStoreURL: URL, to storeURL: URL) -> [(URL, URL)] {
        zip(artifactURLs(for: legacyStoreURL), artifactURLs(for: storeURL)).map { ($0, $1) }
    }

    private static func artifactURLs(for baseStoreURL: URL) -> [URL] {
        ["", "-shm", "-wal"].map { suffix in
            URL(fileURLWithPath: baseStoreURL.path(percentEncoded: false) + suffix)
        }
    }

    private static func legacyStoreContainsNetworkAnnotations(at storeURL: URL) -> Bool {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            storeURL.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            sqlite3_close(database)
            return false
        }
        defer { sqlite3_close(database) }

        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, compatibilityTableName, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW
    }
}
