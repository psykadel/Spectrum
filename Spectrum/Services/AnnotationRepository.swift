import Foundation
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
