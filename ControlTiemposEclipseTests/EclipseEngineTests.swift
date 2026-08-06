/// EclipseEngineTests.swift
/// Acceptance tests for `EclipseEngine`, anchored to external published references.
///
/// ## Design principle
/// Every expected value here comes from a **published third-party source**, never from
/// this engine's own output. A test that asserts what the code already prints proves
/// nothing; these compare against NASA/GSFC and xjubier.free.fr.
///
/// ## Reference sources
/// 1. **NASA/GSFC path table** — `eclipse.gsfc.nasa.gov/SEpath/SEpath2001/SE2026Aug12Tpath.html`
///    Central-line coordinates, sun altitude, path width and central duration every 2 min.
/// 2. **NASA/GSFC Besselian elements** — `.../SEbeselm/SEbeselm2001/SE2026Aug12Tbeselm.html`
///    Used by `datasetMatchesPublishedElements` to guard the bundled dataset directly.
/// 3. **xjubier.free.fr** — Xavier Jubier's interactive map, read on 2026-07-31 for the
///    two Spanish sites below. Jubier uses a modern JPL ephemeris and ΔT = 69.1 s.
///
/// ## Known, deliberate offsets against NASA
/// The bundled 2026 elements were regenerated from JPL DE440s (see
/// `scripts/validate_besselian.py`) with two documented choices that differ from Espenak:
/// * **ΔT = 69.1 s** (Jubier's current estimate) instead of Espenak's older 71.4 s
///   prediction. Shifts every UTC contact ~2.3 s later.
/// * **Lunar radius k = 0.2725076 (IAU)** for both cones instead of Espenak's
///   k2 = 0.272281 "Watts mean limb" value. Widens the umbra ~3 km, so central
///   durations run ~2 s longer than the NASA table.
/// Residuals against the NASA path table are therefore ~+4 s in maximum and ~+2 s in
/// duration, and the tolerances below are sized around that.
///
/// ## Why Raimat is not asserted total or partial
/// Raimat Natura sits within ~5 km of the northern limit — inside the disagreement
/// between the best available sources (xjubier places it 4.9 km inside; elements of the
/// Espenak lineage place it 1–2 km outside). Asserting either verdict would encode a
/// coin flip as a requirement, so `raimatIsMarginal` asserts only that the site is at
/// the edge, which is the fact that actually matters operationally.

import Testing
import Foundation
@testable import ControlTiemposEclipse

// MARK: - Helpers

/// Builds a UTC `Date` at noon on the given calendar day.
private func utcDate(year: Int, month: Int, day: Int) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = 12
    c.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: c)!
}

/// Builds a UTC `Date` on eclipse day 2026-08-12 at the given time.
private func utcOnEclipseDay(_ hh: Int, _ mm: Int, _ ss: Double = 0) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = 8; c.day = 12
    c.hour = hh; c.minute = mm; c.second = Int(ss)
    c.timeZone = TimeZone(identifier: "UTC")
    let base = Calendar(identifier: .gregorian).date(from: c)!
    return base.addingTimeInterval(ss - Double(Int(ss)))
}

/// The eclipse day, for `circumstances(lat:lon:date:)`.
private let eclipseDay = utcDate(year: 2026, month: 8, day: 12)

/// One row of the NASA/GSFC path table for the 2026 Aug 12 eclipse.
private struct PathRow {
    let ut: (Int, Int)       // instante tabulado (UT)
    let lat, lon: Double     // línea central
    let duration: Double     // duración central en segundos
    let sunAltitude: Double  // altura del Sol en grados
}

/// Central-line rows spanning the whole track, from the Arctic to the Mediterranean.
private let nasaPath: [PathRow] = [
    PathRow(ut: (17, 20), lat: 79.77333, lon: -26.98167, duration: 130.0, sunAltitude: 21),
    PathRow(ut: (17, 34), lat: 71.45000, lon: -27.36167, duration: 136.8, sunAltitude: 25),
    PathRow(ut: (17, 46), lat: 65.17167, lon: -25.20500, duration: 138.2, sunAltitude: 26),
    PathRow(ut: (18, 00), lat: 58.27167, lon: -21.57333, duration: 135.3, sunAltitude: 24),
    PathRow(ut: (18, 16), lat: 50.33333, lon: -15.31667, duration: 125.2, sunAltitude: 19),
    PathRow(ut: (18, 28), lat: 43.37167, lon:  -6.18833, duration: 109.3, sunAltitude: 10),
    PathRow(ut: (18, 30), lat: 41.81667, lon:  -3.18500, duration: 104.6, sunAltitude:  8),
]

// MARK: - Tests

@Suite("EclipseEngine — validación contra fuentes publicadas")
struct EclipseEngineTests {

    // MARK: 1. Dataset — los elementos coinciden con los publicados

    /// Guards the bundled 2026 elements against the values published by NASA/Espenak.
    ///
    /// This is the test that would have caught the historical defect: a previous dataset
    /// computed `d` and `mu` in J2000 instead of the equator of date, leaving `d[0]` off
    /// by 0.1168° — exactly the J2000→2026 precession — which shifted the umbral path
    /// about 10 km north and made C2/C3 fire 5–7 s early.
    ///
    /// `l2` legitimately differs from the published value because the dataset uses the
    /// IAU lunar radius rather than Espenak's narrower umbral constant.
    @Test("El dataset de 2026 coincide con los elementos publicados por la NASA")
    func datasetMatchesPublishedElements() throws {
        let url = try #require(Bundle.main.url(forResource: "eclipses", withExtension: "json"),
                               "eclipses.json debe estar en el bundle")
        let data = try Data(contentsOf: url)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let all  = try #require(root["eclipses"] as? [[String: Any]])
        let e    = try #require(all.first { $0["date_utc"] as? String == "2026-08-12" },
                                "falta la entrada del 12/08/2026")

        func coefficient(_ key: String) throws -> Double {
            let a = try #require(e[key] as? [Double], "falta el coeficiente \(key)")
            return a[0]
        }

        // Valores publicados: eclipse.gsfc.nasa.gov/SEbeselm/SEbeselm2001/SE2026Aug12Tbeselm.html
        #expect(abs(try coefficient("d")  - 14.79667)  < 0.001,
                "d[0] fuera de tolerancia — ¿coordenadas en J2000 en lugar de equador de la fecha?")
        #expect(abs(try coefficient("mu") - 88.74776)  < 0.001,
                "mu[0] fuera de tolerancia — ¿marco de referencia o meridiano equivocado?")
        #expect(abs(try coefficient("x")  -  0.475593) < 0.0005, "x[0] fuera de tolerancia")
        #expect(abs(try coefficient("y")  -  0.771161) < 0.0005, "y[0] fuera de tolerancia")
        #expect(abs(try coefficient("l1") -  0.537954) < 0.0005, "l1[0] fuera de tolerancia")
        // l2 usa k IAU (0.2725076); Espenak publica -0.008142 con k2 = 0.272281.
        #expect(abs(try coefficient("l2") - (-0.0083647)) < 0.0005, "l2[0] fuera de tolerancia")

        let t0 = try #require(e["t0_tdt_hours"] as? Double)
        #expect(t0 == 18.0, "t0 debe ser 18:00 TDT, como en el Canon")
    }

    // MARK: 2. Trayectoria — instante del máximo sobre la línea central

    /// The instant of maximum on the central line must match the tabulated UT.
    ///
    /// Tolerance ±12 s absorbs the ~+4 s systematic offset from the ΔT choice plus the
    /// rounding of the tabulated coordinates (0.1 arcmin ≈ 185 m).
    @Test("El máximo en la línea central coincide con la tabla de la NASA (±12 s)",
          arguments: nasaPath.indices)
    func maximumMatchesNasaPath(_ i: Int) throws {
        let row = nasaPath[i]
        let c = try #require(EclipseEngine.circumstances(lat: row.lat, lon: row.lon,
                                                         date: eclipseDay),
                             "la línea central debe ver el eclipse en \(row.ut)")
        let maxDate = try #require(c.contacts[.max])
        let reference = utcOnEclipseDay(row.ut.0, row.ut.1)
        let error = maxDate.timeIntervalSince(reference)
        #expect(abs(error) <= 12,
                "MAX en \(row.ut.0):\(row.ut.1) desviado \(error.rounded()) s (tolerancia ±12 s)")
    }

    // MARK: 3. Trayectoria — duración de la totalidad en la línea central

    /// Central-line duration must match the tabulated value.
    ///
    /// Tolerance ±5 s absorbs the ~+2 s from using the IAU lunar radius instead of
    /// Espenak's narrower umbral constant.
    @Test("La duración en la línea central coincide con la tabla de la NASA (±5 s)",
          arguments: nasaPath.indices)
    func durationMatchesNasaPath(_ i: Int) throws {
        let row = nasaPath[i]
        let c = try #require(EclipseEngine.circumstances(lat: row.lat, lon: row.lon,
                                                         date: eclipseDay))
        #expect(c.kind == .total, "la línea central debe ser total en \(row.ut)")
        let d = try #require(c.totalityDurationSeconds)
        #expect(abs(d - row.duration) <= 5,
                "duración en \(row.ut.0):\(row.ut.1): \(d.rounded()) s frente a \(row.duration) s tabulados")
    }

    // MARK: 4. Trayectoria — altura del Sol

    @Test("La altura del Sol coincide con la tabla de la NASA (±1,5°)",
          arguments: nasaPath.indices)
    func sunAltitudeMatchesNasaPath(_ i: Int) throws {
        let row = nasaPath[i]
        let c = try #require(EclipseEngine.circumstances(lat: row.lat, lon: row.lon,
                                                         date: eclipseDay))
        let alt = try #require(c.sunAltitudeAtMax)
        #expect(abs(alt - row.sunAltitude) <= 1.5,
                "altura en \(row.ut.0):\(row.ut.1): \(alt) ° frente a \(row.sunAltitude) ° tabulados")
    }

    // MARK: 5. Zaragoza — contactos contra xjubier

    /// Zaragoza sits well inside the path, so every source agrees it is total; it is the
    /// right place to check absolute contact times.
    ///
    /// Reference (xjubier.free.fr, ΔT = 69.1 s, read 2026-07-31):
    /// C1 17:34:42.9, C2 18:29:03.9, MAX 18:29:46.0, C3 18:30:27.9 UT; totality 84.0 s.
    @Test("Zaragoza: contactos dentro de tolerancia frente a xjubier")
    func zaragozaAgainstJubier() throws {
        let c = try #require(EclipseEngine.circumstances(lat: 41.6488, lon: -0.8891,
                                                         date: eclipseDay),
                             "Zaragoza debe ver el eclipse")
        #expect(c.kind == .total, "Zaragoza es total en todas las fuentes")

        let checks: [(EclipsePhase, Date, TimeInterval, String)] = [
            (.c1,  utcOnEclipseDay(17, 34, 42.9),  5, "C1"),
            (.c2,  utcOnEclipseDay(18, 29,  3.9),  8, "C2"),
            (.max, utcOnEclipseDay(18, 29, 46.0),  8, "MAX"),
            (.c3,  utcOnEclipseDay(18, 30, 27.9), 10, "C3"),
        ]
        for (phase, reference, tolerance, label) in checks {
            let got = try #require(c.contacts[phase], "falta \(label) en Zaragoza")
            let error = got.timeIntervalSince(reference)
            #expect(abs(error) <= tolerance,
                    "\(label) Zaragoza desviado \(error.rounded()) s de xjubier (tolerancia ±\(Int(tolerance)) s)")
        }

        let d = try #require(c.totalityDurationSeconds)
        #expect(abs(d - 84.0) <= 6,
                "totalidad en Zaragoza \(d.rounded()) s frente a 84,0 s de xjubier")
    }

    // MARK: 6. Raimat — el punto de observación está en el borde

    /// Raimat Natura is a few kilometres from the northern limit, and reputable sources
    /// disagree on which side of it the site falls. The test asserts the fact that is
    /// robust — that the site is grazing the limit — and pins C1, a penumbral contact
    /// that every source agrees on to well under a second.
    @Test("Raimat está sobre el límite de la franja, no claramente dentro ni fuera")
    func raimatIsMarginal() throws {
        let c = try #require(EclipseEngine.circumstances(lat: 41.68294, lon: 0.47930,
                                                         date: eclipseDay),
                             "Raimat debe ver al menos un eclipse parcial")
        let magnitude = try #require(c.magnitude)
        #expect(magnitude > 0.995 && magnitude < 1.005,
                "Raimat debería salir rasante (magnitud ≈ 1), se obtuvo \(magnitude)")

        // C1 es un contacto penumbral: robusto frente al modelo. xjubier: 17:34:39.1 UT.
        let c1 = try #require(c.contacts[.c1])
        let error = c1.timeIntervalSince(utcOnEclipseDay(17, 34, 39.1))
        #expect(abs(error) <= 5,
                "C1 Raimat desviado \(error.rounded()) s de xjubier (tolerancia ±5 s)")
    }

    // MARK: 7. Clasificación en puntos inequívocos

    @Test("Sevilla ve un eclipse parcial, sin C2 ni C3")
    func sevillaIsPartial() throws {
        let c = try #require(EclipseEngine.circumstances(lat: 37.383, lon: -5.997,
                                                         date: eclipseDay),
                             "Sevilla debe ver el eclipse como parcial")
        #expect(c.kind == .partial, "se esperaba parcial, se obtuvo \(c.kind)")
        #expect(c.contacts[.c2] == nil, "un eclipse parcial no tiene C2")
        #expect(c.contacts[.c3] == nil, "un eclipse parcial no tiene C3")
    }

    /// Confirmed total by PhotoPills. Also the case that exposed the old H = μ − λ sign error.
    @Test("Islandia (64.90 N, 23.71 W) ve la totalidad")
    func icelandIsTotal() throws {
        let c = try #require(EclipseEngine.circumstances(lat: 64.8975, lon: -23.706,
                                                         date: eclipseDay),
                             "el punto de Islandia debe ver el eclipse")
        #expect(c.kind == .total, "se esperaba total, se obtuvo \(c.kind)")
        let d = try #require(c.totalityDurationSeconds)
        #expect(d >= 90 && d <= 150, "duración en Islandia \(d.rounded()) s fuera de 90–150 s")
    }

    /// The penumbra reaches Tokyo geometrically, but the Sun is below the horizon there.
    @Test("Tokio no ve el eclipse: el Sol está bajo el horizonte")
    func tokyoSeesNothing() {
        let c = EclipseEngine.circumstances(lat: 35.7, lon: 139.7, date: eclipseDay)
        #expect(c == nil, "Tokio no debería ver el eclipse del 12/08/2026")
    }

    // MARK: 8. Selección del próximo eclipse visible

    @Test("El próximo eclipse visible desde Raimat es el del 12/08/2026")
    func nextVisibleFromRaimat() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let from = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let next = try #require(EclipseEngine.nextVisibleEclipseDate(lat: 41.68294,
                                                                     lon: 0.47930,
                                                                     after: from))
        let comps = cal.dateComponents([.year, .month, .day], from: next)
        #expect(comps.year == 2026 && comps.month == 8 && comps.day == 12,
                "se esperaba 2026-08-12, se obtuvo \(comps)")
    }
}


// MARK: - ExternalLinks

/// Contract tests for the external website deep links.
///
/// These live in this file rather than their own because the test target references its
/// sources explicitly (no synchronised group), and CLAUDE.md forbids hand-editing the
/// `.pbxproj`. Drag them out into `ExternalLinksTests.swift` from Xcode whenever
/// convenient — nothing here depends on the file name.
///
/// The URLs fail silently: a decimal comma instead of a point, or a stray fractional
/// second in the ISO date, produces a link the remote site quietly misreads and the app
/// has no way to notice. The point of these tests is to pin the exact strings.

@Suite("ExternalLinks — URLs de verificación externa")
struct ExternalLinksTests {

    // MARK: - Fixtures

    /// Raimat Natura, Lleida — el punto de referencia del proyecto.
    private static let raimatLat = 41.68294
    private static let raimatLon = 0.47930

    /// Máximo del eclipse del 12/08/2026 sobre Raimat: 18:29:20 UTC.
    private static let maximum = Date(timeIntervalSince1970: 1_786_559_360)

    /// Circunstancias mínimas para construir el enlace de PeakFinder.
    ///
    /// - Parameters:
    ///   - azimuth:  Azimut solar en el máximo, o `nil` para probar el caso degenerado.
    ///   - altitude: Altura solar en el máximo, o `nil` para probar el caso degenerado.
    private static func circumstances(azimuth: Double?, altitude: Double?) -> EclipseCircumstances {
        EclipseCircumstances(
            kind: .total,
            contacts: [.max: maximum],
            magnitude: 1.0,
            sunAltitudeAtMax: altitude,
            sunAzimuthAtMax: azimuth,
            obscuration: 1.0,
            totalityDurationSeconds: 80
        )
    }

    // MARK: - peakfinder.com

    @Test("La URL de PeakFinder lleva coordenadas, puntería solar y fecha del máximo")
    func peakFinderURLIsExact() throws {
        let url = try #require(ExternalLinks.peakFinder(
            latitude:      Self.raimatLat,
            longitude:     Self.raimatLon,
            name:          "Raimat Natura",
            circumstances: Self.circumstances(azimuth: 285.4, altitude: 5.0)
        ))

        #expect(url.absoluteString == "https://www.peakfinder.com/?"
            + "lat=41.68294"
            + "&lng=0.47930"
            + "&name=Raimat%20Natura"
            + "&azi=285.4"
            + "&alt=5.0"
            + "&fov=60"
            + "&date=2026-08-12T18:29:20Z"
            + "&teleazi=285.4"
            + "&telealt=5.0")
    }

    @Test("Sin nombre de localización se omite el parámetro name")
    func peakFinderURLOmitsEmptyName() throws {
        let url = try #require(ExternalLinks.peakFinder(
            latitude:      Self.raimatLat,
            longitude:     Self.raimatLon,
            name:          "",
            circumstances: Self.circumstances(azimuth: 285.4, altitude: 5.0)
        ))

        #expect(!url.absoluteString.contains("name="))
    }

    /// La cámara de PeakFinder solo admite ±25° de inclinación, pero el marcador
    /// telescopio debe seguir señalando la posición real del Sol.
    @Test("Un Sol alto acota la cámara a 25° pero no el marcador telescopio")
    func peakFinderClampsCameraButNotTelescope() throws {
        let url = try #require(ExternalLinks.peakFinder(
            latitude:      Self.raimatLat,
            longitude:     Self.raimatLon,
            name:          nil,
            circumstances: Self.circumstances(azimuth: 180.0, altitude: 61.3)
        ))

        #expect(url.absoluteString.contains("&alt=25.0"))
        #expect(url.absoluteString.contains("&telealt=61.3"))
    }

    @Test("Sin posición solar no hay enlace de PeakFinder")
    func peakFinderNeedsSunPosition() {
        #expect(ExternalLinks.peakFinder(
            latitude:      Self.raimatLat,
            longitude:     Self.raimatLon,
            name:          "Raimat",
            circumstances: Self.circumstances(azimuth: nil, altitude: 5.0)
        ) == nil)

        #expect(ExternalLinks.peakFinder(
            latitude:      Self.raimatLat,
            longitude:     Self.raimatLon,
            name:          "Raimat",
            circumstances: Self.circumstances(azimuth: 285.4, altitude: nil)
        ) == nil)
    }

    /// Los separadores decimales deben ser puntos pase lo que pase: es exactamente el
    /// fallo que la versión de Android arrastraba con `String.format` sin locale.
    @Test("Los números de la URL usan punto decimal, no coma")
    func peakFinderUsesDecimalPoint() throws {
        let url = try #require(ExternalLinks.peakFinder(
            latitude:      Self.raimatLat,
            longitude:     Self.raimatLon,
            name:          nil,
            circumstances: Self.circumstances(azimuth: 285.4, altitude: 5.0)
        ))

        #expect(!url.absoluteString.contains(","))
    }

    // MARK: - xjubier.free.fr

    @Test("La URL de xjubier apunta al mapa del eclipse con las coordenadas cargadas")
    func xjubierURLIsExact() throws {
        let url = try #require(ExternalLinks.xjubier(
            latitude:  Self.raimatLat,
            longitude: Self.raimatLon,
            eclipseID: "SE2026Aug12T",
            year:      2026
        ))

        #expect(url.absoluteString == "http://xjubier.free.fr/en/site_pages/solar_eclipses/"
            + "TSE_2026_GoogleMapFull.html?"
            + "Lat=41.68294&Lng=0.47930&Elv=0&Zoom=18&LC=1")
    }

    @Test("Cada tipo global de eclipse elige su prefijo de fichero",
          arguments: [("SE2026Aug12T", "TSE"), ("SE2027Feb06A", "ASE"), ("SE2031Nov14H", "HSE")])
    func xjubierPrefixPerKind(id: String, prefix: String) throws {
        let url = try #require(ExternalLinks.xjubier(
            latitude: 0, longitude: 0, eclipseID: id, year: 2026
        ))
        #expect(url.absoluteString.contains("/\(prefix)_2026_GoogleMapFull.html"))
    }

    /// Los eclipses globalmente parciales no tienen página GoogleMapFull en xjubier.
    @Test("Un eclipse globalmente parcial no genera enlace")
    func xjubierSkipsGlobalPartial() {
        #expect(ExternalLinks.xjubier(
            latitude: 0, longitude: 0, eclipseID: "SE2025Mar29P", year: 2025
        ) == nil)
    }
}
