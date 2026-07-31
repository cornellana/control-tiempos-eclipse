/// BackupFile.swift — Data model and service for .cteprog backup archives.
///
/// A `.cteprog` file is a JSON-encoded `BackupFile` containing one or more
/// `BackupProgram` entries, each carrying its full event list as `ProgramEventSnapshot`.
/// Register `com.cornellana.cteprog` as an Exported Type Identifier in Xcode → Target → Info
/// so that iOS routes tapped `.cteprog` files directly to this app.

import Foundation
import UniformTypeIdentifiers

// MARK: - BackupProgram

/// Serialisable representation of a single saved program inside a backup archive.
struct BackupProgram: Codable {

    /// User-assigned program name.
    var name: String

    /// Original creation date, preserved so restore history is meaningful.
    var createdAt: Date

    /// Ordered list of event snapshots.
    var events: [ProgramEventSnapshot]

    /// - Parameter program: The live `SavedProgram` to snapshot.
    init(from program: SavedProgram) {
        name      = program.name
        createdAt = program.createdAt
        events    = program.decodedEvents
    }
}

// MARK: - BackupFile

/// Top-level container of a `.cteprog` backup archive.
struct BackupFile: Codable {

    /// Schema version. Increment when the format changes incompatibly.
    let version: Int

    /// Programs included in this archive.
    var programs: [BackupProgram]

    /// - Parameter programs: The `SavedProgram` records to archive.
    init(from programs: [SavedProgram]) {
        version       = 1
        self.programs = programs.map { BackupProgram(from: $0) }
    }
}

// MARK: - IdentifiableBackup

/// Identifiable wrapper for `BackupFile` used with `.sheet(item:)`.
///
/// `.sheet(item:)` guarantees the sheet content closure always receives a non-nil
/// value, eliminating the race condition that causes a blank gray sheet when using
/// `.sheet(isPresented:)` with a separate optional state variable.
struct IdentifiableBackup: Identifiable {
    let id     = UUID()
    let backup: BackupFile
}

// MARK: - BackupService

/// Stateless helpers for creating and parsing `.cteprog` backup files.
enum BackupService {

    /// File extension used for all backup archives.
    static let fileExtension = "cteprog"

    /// UTI for the custom backup format.
    ///
    /// For iOS to route tapped `.cteprog` files directly to this app, register
    /// `com.cornellana.cteprog` under **Exported Type Identifiers** and add a matching
    /// **Document Type** entry in Xcode → Target → Info.
    static let contentType = UTType(exportedAs: "com.cornellana.cteprog")

    /// Serialises the given programs into a temporary `.cteprog` file and returns its URL.
    ///
    /// - Parameter programs: `SavedProgram` records to include.
    /// - Returns: Temporary file URL suitable for `UIActivityViewController`.
    /// - Throws: `EncodingError` or file-write errors.
    static func export(programs: [SavedProgram]) throws -> URL {
        let backup  = BackupFile(from: programs)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        let data    = try encoder.encode(backup)

        let formatter        = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "EclipsePrograms-\(formatter.string(from: Date())).\(fileExtension)"
        let url      = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Reads and decodes a `.cteprog` file at the given URL.
    ///
    /// - Parameter url: URL of the backup file. The caller must hold a valid
    ///   security-scoped access grant when the file comes from a `fileImporter` result.
    /// - Returns: The decoded `BackupFile`.
    /// - Throws: File-read or `DecodingError`.
    static func importFile(from url: URL) throws -> BackupFile {
        let data    = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }
}
