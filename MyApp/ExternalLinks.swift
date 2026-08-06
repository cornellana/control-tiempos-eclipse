/// ExternalLinks.swift — Deep links to the external eclipse-planning websites.
///
/// Two independent services are linked from the verification card:
///
///   • **xjubier.free.fr** — Xavier Jubier's interactive eclipse map. Answers
///     "do my coordinates fall inside the totality band?".
///   • **peakfinder.com** — mountain panorama renderer. Answers "is anything
///     standing between me and the Sun?", which matters enormously when the
///     eclipse happens near the horizon (5° of solar altitude at Raimat on
///     2026-08-12: a 90 m hill one kilometre away hides totality entirely).
///
/// URL building lives here rather than inside the views for one concrete reason:
/// these strings fail silently. A decimal comma instead of a point produces a URL
/// that the remote site quietly misreads, and there is no way to notice from the
/// app. Kept as a stateless namespace, it is unit-testable — see
/// `ExternalLinksTests`.

import Foundation

// MARK: - ExternalLinks

/// Builders for the external website links shown on the verification card.
nonisolated enum ExternalLinks {

    // MARK: - Constants

    /// Horizontal field of view requested from PeakFinder, in degrees.
    ///
    /// The Sun sweeps an arc of azimuth between C1 and C4 — about 18° at Raimat on
    /// 2026-08-12 (a low, setting Sun), up to roughly 45° for a midday eclipse.
    /// 60° frames that sweep with margin while keeping the horizon profile legible.
    /// PeakFinder accepts 8…90.
    static let peakFinderFieldOfView = 60

    /// Bounds of PeakFinder's camera pitch (`alt`), in degrees, per its API contract.
    private static let cameraAltitudeRange = -25.0...25.0

    // MARK: - xjubier.free.fr

    /// Builds the URL of xjubier.free.fr's interactive map for a specific eclipse,
    /// pre-centred on the observer's coordinates.
    ///
    /// Verified format:
    /// `http://xjubier.free.fr/en/site_pages/solar_eclipses/TSE_2026_GoogleMapFull.html?Lat=41.68294&Lng=0.47930&Elv=0&Zoom=18&LC=1`
    ///
    /// The filename prefix ("TSE", "ASE", "HSE") comes from the eclipse's global type,
    /// i.e. the last character of the dataset id (`"SE2026Aug12T"` → `T` → `TSE`).
    /// Globally partial eclipses (type `P`) have no dedicated GoogleMapFull page, so
    /// this returns `nil` and the caller hides the button.
    ///
    /// xjubier only publishes this map in English: the `/es/` and `/fr/` paths 404.
    ///
    /// - Parameters:
    ///   - latitude:  Observer latitude in decimal degrees.
    ///   - longitude: Observer longitude in decimal degrees.
    ///   - eclipseID: Dataset identifier of the eclipse, e.g. `"SE2026Aug12T"`.
    ///   - year:      Calendar year of the eclipse in UTC, used in the filename.
    /// - Returns: The map URL, or `nil` for eclipses with no dedicated map page.
    static func xjubier(latitude: Double,
                        longitude: Double,
                        eclipseID: String,
                        year: Int) -> URL? {

        let prefix: String
        switch eclipseID.last {
        case "T": prefix = "TSE"
        case "A": prefix = "ASE"
        case "H": prefix = "HSE"
        default:  return nil    // eclipses globalmente parciales no tienen mapa dedicado
        }

        let filename = "\(prefix)_\(year)_GoogleMapFull.html"
        guard var uc = URLComponents(
            string: "http://xjubier.free.fr/en/site_pages/solar_eclipses/\(filename)"
        ) else { return nil }

        uc.queryItems = [
            URLQueryItem(name: "Lat",  value: decimal(latitude,  places: 5)),
            URLQueryItem(name: "Lng",  value: decimal(longitude, places: 5)),
            URLQueryItem(name: "Elv",  value: "0"),
            URLQueryItem(name: "Zoom", value: "18"),
            URLQueryItem(name: "LC",   value: "1"),
        ]
        return uc.url
    }

    // MARK: - peakfinder.com

    /// Builds the URL of PeakFinder's panorama for the observation point, aimed at the
    /// Sun's position at maximum eclipse.
    ///
    /// Parameters follow the published API (https://github.com/Fabiz/PeakFinder-API):
    ///
    /// | Key | Meaning |
    /// |---|---|
    /// | `lat`, `lng` | Viewpoint (required) |
    /// | `name` | Viewpoint label |
    /// | `azi` | Camera bearing, 0–360 clockwise from North |
    /// | `alt` | Camera pitch, −25…25 |
    /// | `fov` | Field of view, 8–90 |
    /// | `date` | ISO 8601 instant — makes PeakFinder draw that day's Sun and Moon paths |
    /// | `teleazi`, `telealt` | "Telescope" marker pinned to an exact point of the sky |
    ///
    /// `ele` is deliberately omitted: PeakFinder resolves the viewpoint's ground
    /// elevation from its own terrain model, which beats any value the app could supply
    /// (the app never records elevation, and it passes a flat `Elv=0` to xjubier).
    ///
    /// Because `date` is set, PeakFinder renders the whole solar trajectory of the day,
    /// so a single link shows the C1→C4 path against the real horizon profile.
    ///
    /// The engine's `sunAzimuthAtMax` already uses PeakFinder's convention (0° = North,
    /// increasing clockwise), so no conversion is needed.
    ///
    /// - Parameters:
    ///   - latitude:      Observer latitude in decimal degrees.
    ///   - longitude:     Observer longitude in decimal degrees.
    ///   - name:          Optional label for the viewpoint; ignored when empty.
    ///   - circumstances: Computed local circumstances; supplies the maximum's instant
    ///                    and the Sun's altitude and azimuth at that instant.
    /// - Returns: The panorama URL, or `nil` when the circumstances lack the maximum's
    ///            time or the Sun's position (as happens in simulation mode).
    static func peakFinder(latitude: Double,
                           longitude: Double,
                           name: String?,
                           circumstances: EclipseCircumstances) -> URL? {

        guard let maxDate = circumstances.contacts[.max],
              let azimuth = circumstances.sunAzimuthAtMax,
              let altitude = circumstances.sunAltitudeAtMax,
              var uc = URLComponents(string: "https://www.peakfinder.com/") else { return nil }

        // La cámara solo admite ±25° de inclinación; el marcador telescopio va sin
        // acotar para que siga diciendo la verdad aunque el Sol quede fuera del
        // encuadre (un Sol tan alto no lo tapa ningún obstáculo, de todos modos).
        let cameraAltitude = min(max(altitude, cameraAltitudeRange.lowerBound),
                                 cameraAltitudeRange.upperBound)

        var items = [
            URLQueryItem(name: "lat", value: decimal(latitude,  places: 5)),
            URLQueryItem(name: "lng", value: decimal(longitude, places: 5)),
        ]
        if let name, !name.isEmpty {
            items.append(URLQueryItem(name: "name", value: name))
        }
        items += [
            URLQueryItem(name: "azi",     value: decimal(azimuth,        places: 1)),
            URLQueryItem(name: "alt",     value: decimal(cameraAltitude, places: 1)),
            URLQueryItem(name: "fov",     value: String(peakFinderFieldOfView)),
            URLQueryItem(name: "date",    value: iso8601(maxDate)),
            URLQueryItem(name: "teleazi", value: decimal(azimuth,  places: 1)),
            URLQueryItem(name: "telealt", value: decimal(altitude, places: 1)),
        ]
        uc.queryItems = items
        return uc.url
    }

    // MARK: - Formatting helpers

    /// Formats a number with a fixed number of decimal places, always using a decimal
    /// point.
    ///
    /// `String(format:)` without an explicit locale uses the POSIX conventions, so this
    /// is locale-proof by construction. The wrapper exists to make that guarantee
    /// explicit and to keep every query value going through one place.
    private static func decimal(_ value: Double, places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    /// Formats an instant as the ISO 8601 UTC string PeakFinder expects
    /// (`2026-08-12T18:29:20Z`).
    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
