/// SavedLocation.swift — SwiftData model for a named observation location.

import SwiftData
import Foundation

/// A named geographic coordinate saved by the user for quick reuse across sessions.
///
/// Stored with SwiftData alongside `ProgramEvent`. Displayed in Step 1 as a
/// bookmarks sheet; tapping a record populates the coordinate fields instantly.
@Model final class SavedLocation {

    /// Display name chosen by the user (e.g. "Raimat Natura", "Azotea casa").
    var name: String

    /// WGS-84 latitude in decimal degrees (−90…90).
    var latitude: Double

    /// WGS-84 longitude in decimal degrees (−180…180).
    var longitude: Double

    /// Creation date used as secondary sort key.
    var createdAt: Date

    /// - Parameters:
    ///   - name:      Human-readable label for the location.
    ///   - latitude:  Decimal-degree latitude.
    ///   - longitude: Decimal-degree longitude.
    init(name: String, latitude: Double, longitude: Double) {
        self.name      = name
        self.latitude  = latitude
        self.longitude = longitude
        self.createdAt = Date()
    }
}
