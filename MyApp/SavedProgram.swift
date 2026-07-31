/// SavedProgram.swift — SwiftData model for a named snapshot of the event program.

import SwiftData
import Foundation

// MARK: - Snapshot struct (Codable, not a SwiftData model)

/// Serializable representation of a single program event, used inside `SavedProgram`.
/// Not a `@Model` — stored as a JSON blob inside `SavedProgram.eventsJSON`.
struct ProgramEventSnapshot: Codable {
    var phaseRaw: String
    var offsetSeconds: Int
    var message: String
    var textLanguage: String
    var sortIndex: Int

    init(from event: ProgramEvent) {
        phaseRaw      = event.phaseRaw
        offsetSeconds = event.offsetSeconds
        message       = event.message
        textLanguage  = event.textLanguage
        sortIndex     = event.sortIndex
    }
}

// MARK: - SavedProgram

/// A named snapshot of the full list of `ProgramEvent` records, persisted with SwiftData.
///
/// Events are stored as a JSON-encoded `[ProgramEventSnapshot]` to avoid
/// a complex SwiftData to-many relationship. Loading a saved program replaces
/// the active `ProgramEvent` records in the model context.
@Model final class SavedProgram {

    /// User-assigned name, e.g. "Raimat 2026 completo".
    var name: String

    /// JSON-encoded `[ProgramEventSnapshot]`. Use `decodedEvents` to access.
    var eventsJSON: Data

    /// Creation date, used as secondary sort key.
    var createdAt: Date

    /// Number of events — stored explicitly so the list can show it without decoding JSON.
    var eventCount: Int

    /// - Parameters:
    ///   - name:   Human-readable label for this program snapshot.
    ///   - events: Active `ProgramEvent` records to snapshot.
    init(name: String, events: [ProgramEvent]) {
        self.name       = name
        self.createdAt  = Date()
        self.eventCount = events.count
        let snapshots   = events.map { ProgramEventSnapshot(from: $0) }
        self.eventsJSON = (try? JSONEncoder().encode(snapshots)) ?? Data()
    }

    /// Creates a `SavedProgram` from a decoded `BackupProgram`, preserving the original creation date.
    ///
    /// Used during restore to reconstruct the program in a new device's SwiftData store.
    /// - Parameter backup: The backup entry to restore.
    init(from backup: BackupProgram) {
        self.name       = backup.name
        self.createdAt  = backup.createdAt
        self.eventCount = backup.events.count
        self.eventsJSON = (try? JSONEncoder().encode(backup.events)) ?? Data()
    }

    /// Decodes and returns the stored event snapshots.
    var decodedEvents: [ProgramEventSnapshot] {
        (try? JSONDecoder().decode([ProgramEventSnapshot].self, from: eventsJSON)) ?? []
    }
}
