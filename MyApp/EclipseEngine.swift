/// EclipseEngine.swift
/// Computes local solar eclipse circumstances from Besselian elements.
///
/// Algorithm:
///   Meeus, J. (1998). *Astronomical Algorithms*, 2nd ed., chapters 54–55.
///   Espenak, F. & Meeus, J. (2009). *Five Millennium Canon of Solar Eclipses*,
///   NASA Technical Publication TP-2009-214174.
///
/// The embedded dataset (eclipses.json) covers all solar eclipses 2025–2035.

import Foundation

// MARK: - Domain types

/// Type of solar eclipse as experienced by the local observer.
enum EclipseKind: String, Codable, Equatable {
    /// Observer is inside the umbral cone (total eclipse).
    case total
    /// Observer is inside the antumbral cone (annular eclipse).
    case annular
    /// Observer only sees a partial eclipse (outside the central band).
    case partial
    /// Hybrid eclipse; from this point it may be total or annular.
    case hybrid
    /// Simulated eclipse: no real data, phases are generated artificially.
    case simulated
}

/// Phases of a solar eclipse.
enum EclipsePhase: String, Codable, CaseIterable, Equatable {
    /// First external contact: Moon first touches the solar disk.
    case c1
    /// Second contact: beginning of totality or annularity.
    case c2
    /// Local maximum eclipse.
    case max
    /// Third contact: end of totality or annularity.
    case c3
    /// Fourth contact: Moon leaves the solar disk.
    case c4
}

/// Local eclipse circumstances, either computed from Besselian elements or simulated.
struct EclipseCircumstances: Equatable {

    /// Eclipse type at the observer's location.
    let kind: EclipseKind

    /// UTC timestamps for each eclipse phase.
    /// C2 and C3 are absent for partial eclipses.
    let contacts: [EclipsePhase: Date]

    /// Eclipse magnitude at maximum (fraction of solar diameter covered).
    /// Exceeds 1.0 for total and annular eclipses.
    let magnitude: Double?

    /// Solar altitude at maximum eclipse, in degrees above the horizon.
    let sunAltitudeAtMax: Double?

    /// Solar azimuth at maximum eclipse, in degrees from North (clockwise).
    let sunAzimuthAtMax: Double?

    /// Fraction of the solar disk area covered by the Moon at maximum (0.0–1.0).
    /// - 1.0 for total eclipses (solar disk fully covered).
    /// - k² for annular/hybrid eclipses (k = apparent lunar/solar radius ratio).
    /// - Circle-intersection area fraction for partial eclipses.
    /// - nil for simulated eclipses.
    let obscuration: Double?

    /// Duration of totality or annularity in seconds. Nil for partial eclipses.
    let totalityDurationSeconds: Double?
}

// MARK: - Private dataset types

/// Cubic polynomial: a0 + a1·t + a2·t² + a3·t³
private struct Polynomial: Decodable {
    let a0, a1, a2, a3: Double

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        a0 = try c.decode(Double.self)
        a1 = try c.decode(Double.self)
        a2 = (try? c.decode(Double.self)) ?? 0.0
        a3 = (try? c.decode(Double.self)) ?? 0.0
    }

    /// Evaluates the polynomial at t hours from the reference epoch.
    func eval(_ t: Double) -> Double {
        a0 + t * (a1 + t * (a2 + t * a3))
    }

    /// Returns the first derivative with respect to t.
    func deriv(_ t: Double) -> Double {
        a1 + t * (2.0 * a2 + t * 3.0 * a3)
    }
}

/// One eclipse record from the Besselian element dataset.
private struct BesselianEclipse: Decodable {
    let id: String
    /// Calendar date in UTC, formatted "YYYY-MM-DD".
    let date_utc: String
    /// Eclipse type: "total" | "annular" | "partial" | "hybrid".
    let type: String
    /// Reference time of the elements in TDT, in decimal hours from midnight.
    let t0_tdt_hours: Double
    /// ΔT = TDT − UTC, in seconds, at the time of the eclipse.
    let delta_t_seconds: Double
    let x: Polynomial    // x(t): fundamental-plane X coordinate
    let y: Polynomial    // y(t): fundamental-plane Y coordinate
    let d: Polynomial    // d(t): solar declination, degrees
    let l1: Polynomial   // l1(t): penumbral cone radius at the fundamental plane
    let l2: Polynomial   // l2(t): umbral cone radius (negative during totality)
    let mu: Polynomial   // μ(t): Greenwich hour angle of the Sun, degrees
    let tan_f1: Double   // tan of the penumbral cone half-angle
    let tan_f2: Double   // tan of the umbral cone half-angle
}

/// A dataset entry with its calendar date already parsed.
///
/// `date_utc` arrives as a "YYYY-MM-DD" string, and every lookup used to re-parse it with
/// `DateFormatter` — 24 parses per query, which dominated the cost of `findEclipse` and
/// `nextVisibleEclipseDate`. Parsing once at load time makes lookups pure arithmetic.
private struct DatedEclipse {
    let eclipse: BesselianEclipse
    /// Midnight UTC of `eclipse.date_utc`.
    let midnightUTC: Date
}

private struct EclipseDataset: Decodable {
    let eclipses: [BesselianEclipse]
}

// MARK: - EclipseEngine

/// Offline engine that computes local solar eclipse circumstances from embedded Besselian elements.
///
/// All calculations follow the classical algorithm of Meeus (1998), chapters 54–55.
/// The engine uses `eclipses.json`, bundled inside the app, which covers 2025–2035.
/// No network access or external dependencies are required.
///
/// ## Usage
/// ```swift
/// let result = EclipseEngine.circumstances(lat: 41.683, lon: 0.479, date: someDate)
/// ```
struct EclipseEngine {

    // MARK: - Public API

    /// Computes local eclipse circumstances for an observer at the given location and date.
    ///
    /// Returns `nil` when no eclipse exists in the dataset for the given date,
    /// or when the eclipse is not visible from the given location (observer outside penumbra).
    ///
    /// - Parameters:
    ///   - lat: Observer geographic latitude in decimal degrees (−90…90). North is positive.
    ///   - lon: Observer geographic longitude in decimal degrees (−180…180). East is positive.
    ///   - date: Date to query; only the UTC calendar day is used, not the time component.
    /// - Returns: `EclipseCircumstances` if the eclipse is visible; `nil` otherwise.
    static func circumstances(lat: Double, lon: Double, date: Date) -> EclipseCircumstances? {
        guard let dated = findDated(for: date) else { return nil }
        return compute(dated: dated, lat: lat, lon: lon)
    }

    /// Returns true when the dataset contains any eclipse on the given UTC calendar date,
    /// without checking local visibility.
    ///
    /// - Parameter date: Date to query.
    /// - Returns: `true` if an eclipse exists in the dataset for that date.
    static func hasEclipse(for date: Date) -> Bool {
        findEclipse(for: date) != nil
    }

    /// Returns the xjubier.free.fr eclipse page identifier for the eclipse on the given date.
    ///
    /// The identifier follows the format used as the subdirectory name in xjubier URLs,
    /// e.g. "SE2026Aug12T". It corresponds to the `id` field in the embedded dataset.
    ///
    /// - Parameter date: Date to query; only the UTC calendar day is used.
    /// - Returns: The eclipse identifier string, or `nil` when no eclipse is found.
    static func xjubierID(for date: Date) -> String? {
        findEclipse(for: date)?.id
    }

    /// Finds the next eclipse visible from the given location that occurs after `after`.
    ///
    /// Iterates the embedded dataset in calendar order and returns the midnight UTC `Date`
    /// of the first eclipse for which `circumstances(lat:lon:date:)` returns a non-nil result.
    ///
    /// - Parameters:
    ///   - lat: Observer latitude in decimal degrees.
    ///   - lon: Observer longitude in decimal degrees.
    ///   - after: Search for eclipses strictly after this date.
    /// - Returns: Midnight UTC of the next visible eclipse, or `nil` if none found in the dataset.
    static func nextVisibleEclipseDate(lat: Double, lon: Double, after: Date) -> Date? {
        let startOfAfter = utcCalendar.startOfDay(for: after)
        return dataset
            .compactMap { dated -> Date? in
                guard dated.midnightUTC > startOfAfter else { return nil }
                guard compute(dated: dated, lat: lat, lon: lon) != nil else { return nil }
                return dated.midnightUTC
            }
            .min()
    }

    // MARK: - Dataset

    /// Eclipses del bundle, cada uno con su fecha ya convertida a `Date`.
    ///
    /// Se resuelve una sola vez (`static let`) y de forma segura para hilos.
    private static let dataset: [DatedEclipse] = {
        // Cargar el fichero eclipses.json del bundle en el arranque.
        guard let url  = Bundle.main.url(forResource: "eclipses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let ds   = try? JSONDecoder().decode(EclipseDataset.self, from: data) else {
            assertionFailure("eclipses.json no encontrado o corrupto en el bundle.")
            return []
        }
        // Las fechas se parsean aquí, no en cada consulta.
        return ds.eclipses.compactMap { eclipse in
            guard let midnight = parseMidnightUTC(eclipse.date_utc) else { return nil }
            return DatedEclipse(eclipse: eclipse, midnightUTC: midnight)
        }
    }()

    /// Calendario UTC reutilizable — construirlo en cada consulta era gasto puro.
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }()

    /// Finds the eclipse whose UTC date matches the given date, accepting a ±1-day window
    /// to handle timezone edge cases.
    private static func findDated(for date: Date) -> DatedEclipse? {
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard let targetMidnight = utcCalendar.date(from: comps) else { return nil }

        return dataset.first {
            abs($0.midnightUTC.timeIntervalSince(targetMidnight)) < 86_400
        }
    }

    /// Convenience accessor returning only the Besselian elements.
    private static func findEclipse(for date: Date) -> BesselianEclipse? {
        findDated(for: date)?.eclipse
    }

    /// Formateador reutilizable para parsear "YYYY-MM-DD".
    ///
    /// DateFormatter es caro de inicializar (la primera llamada dispara la carga de ICU,
    /// que puede tardar hasta 15 s en iOS si se hace en el hilo principal). Al ser un
    /// static let, Swift garantiza que la inicialización ocurre solo una vez y de forma
    /// segura para hilos (thread-safe).
    private static let utcDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone   = TimeZone(identifier: "UTC")!
        fmt.locale     = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    /// Parses "YYYY-MM-DD" to midnight UTC as a `Date`.
    ///
    /// Only called while building `dataset`; lookups use the cached `DatedEclipse.midnightUTC`.
    private static func parseMidnightUTC(_ string: String) -> Date? {
        utcDateFormatter.date(from: string)
    }

    // MARK: - Besselian element evaluation

    /// All Besselian element values and their first derivatives evaluated at one instant.
    private struct Elements {
        // Valores evaluados en t
        let x, y, d, l1, l2, mu: Double
        // Primeras derivadas respecto a t (unidades/hora)
        let dx, dy, dd, dl1, dl2, dmu: Double
    }

    /// Evaluates all Besselian elements and their derivatives at t hours (TDT) from t0.
    private static func elements(eclipse: BesselianEclipse, t: Double) -> Elements {
        Elements(
            x:   eclipse.x.eval(t),    y:   eclipse.y.eval(t),
            d:   eclipse.d.eval(t),    l1:  eclipse.l1.eval(t),
            l2:  eclipse.l2.eval(t),   mu:  eclipse.mu.eval(t),
            dx:  eclipse.x.deriv(t),   dy:  eclipse.y.deriv(t),
            dd:  eclipse.d.deriv(t),   dl1: eclipse.l1.deriv(t),
            dl2: eclipse.l2.deriv(t),  dmu: eclipse.mu.deriv(t)
        )
    }

    // MARK: - Observer projection onto the fundamental plane

    /// Observer's coordinates in the Besselian fundamental plane and their time derivatives.
    private struct ObserverFP {
        let xi, eta, zeta: Double   // posición en el plano fundamental
        let dxi, deta: Double       // derivadas temporales (por hora)
    }

    /// Projects the observer onto the Besselian fundamental plane.
    ///
    /// Implements equations (54.1)–(54.5) of Meeus (1998), assuming observer height h = 0.
    ///
    /// - Parameters:
    ///   - rhoSinPhi: ρ sin φ′ — geocentric polar component of the observer.
    ///   - rhoCosPhi: ρ cos φ′ — geocentric equatorial component.
    ///   - lon: Observer longitude in degrees (East positive).
    ///   - el: Besselian elements evaluated at the current time.
    private static func observerFP(rhoSinPhi: Double, rhoCosPhi: Double,
                                    lon: Double, el: Elements) -> ObserverFP {
        // Ángulo horario local H = μ − L_west (Meeus §54). L_west = −lon_east → H = μ + lon.
        let H    = (el.mu + lon) * .pi / 180.0
        let dRad = el.d   * .pi / 180.0
        // Velocidades angulares en rad/hora
        let mu1  = el.dmu * .pi / 180.0
        let d1   = el.dd  * .pi / 180.0

        // Coordenadas (ξ, η, ζ) en el plano fundamental — Meeus (54.2)
        let xi   = rhoCosPhi * sin(H)
        let eta  = rhoSinPhi * cos(dRad) - rhoCosPhi * cos(H) * sin(dRad)
        let zeta = rhoSinPhi * sin(dRad) + rhoCosPhi * cos(H) * cos(dRad)

        // Derivadas temporales de (ξ, η) — Meeus (54.4)
        let dxi  = rhoCosPhi * cos(H) * mu1
        let deta = -rhoSinPhi * sin(dRad) * d1
                 + rhoCosPhi  * sin(H)    * sin(dRad) * mu1
                 - rhoCosPhi  * cos(H)    * cos(dRad) * d1

        return ObserverFP(xi: xi, eta: eta, zeta: zeta, dxi: dxi, deta: deta)
    }

    // MARK: - Core computation

    /// Computes local eclipse circumstances for a given Besselian eclipse and observer location.
    private static func compute(dated: DatedEclipse,
                                lat: Double, lon: Double) -> EclipseCircumstances? {
        let eclipse  = dated.eclipse
        let midnight = dated.midnightUTC

        // Coordenadas geocéntricas del observador a nivel del mar (h = 0).
        // u = atan(0.99664719 · tan φ)  →  ρ cos φ′ = cos u,  ρ sin φ′ = 0.99664719 · sin u
        // Ref: Meeus (1998), p. 375.
        let phi       = lat * .pi / 180.0
        let u         = atan(0.99664719 * tan(phi))
        let rhoSin    = 0.99664719 * sin(u)
        let rhoCos    = cos(u)

        // Tiempo del máximo eclipse local.
        let tMax = findMaximum(eclipse: eclipse,
                               rhoSinPhi: rhoSin, rhoCosPhi: rhoCos, lon: lon)

        // Evaluación en el máximo.
        let elMax  = elements(eclipse: eclipse, t: tMax)
        let obsMax = observerFP(rhoSinPhi: rhoSin, rhoCosPhi: rhoCos, lon: lon, el: elMax)

        let U        = elMax.x - obsMax.xi
        let V        = elMax.y - obsMax.eta
        let deltaMax = sqrt(U * U + V * V)

        // Radios de los conos a la altura del observador.
        let l1Obs = elMax.l1 - obsMax.zeta * eclipse.tan_f1
        let l2Obs = elMax.l2 - obsMax.zeta * eclipse.tan_f2

        // Sin eclipse si el observador está fuera del cono de penumbra.
        guard deltaMax < l1Obs else { return nil }

        // Tipo de eclipse desde esta localización.
        let absL2 = abs(l2Obs)
        let kind: EclipseKind
        if deltaMax <= absL2 {
            switch eclipse.type {
            case "total":   kind = .total
            case "annular": kind = .annular
            case "hybrid":  kind = .hybrid
            default:        kind = .partial
            }
        } else {
            kind = .partial
        }

        // Calcular contactos.
        var contacts: [EclipsePhase: Date] = [:]
        contacts[.max] = tdtToDate(midnightUTC: midnight, eclipse: eclipse, tTDT: tMax)

        // C1 y C4: primer y último contacto con la penumbra.
        if let tC1 = findContact(eclipse: eclipse,
                                  rhoSinPhi: rhoSin, rhoCosPhi: rhoCos, lon: lon,
                                  tNear: tMax, cone: .penumbra, sign: -1) {
            contacts[.c1] = tdtToDate(midnightUTC: midnight, eclipse: eclipse, tTDT: tC1)
        }
        if let tC4 = findContact(eclipse: eclipse,
                                  rhoSinPhi: rhoSin, rhoCosPhi: rhoCos, lon: lon,
                                  tNear: tMax, cone: .penumbra, sign: +1) {
            contacts[.c4] = tdtToDate(midnightUTC: midnight, eclipse: eclipse, tTDT: tC4)
        }

        // C2 y C3: contactos con la umbra/antumbra (solo en totales, anulares e híbridos).
        if kind != .partial {
            if let tC2 = findContact(eclipse: eclipse,
                                      rhoSinPhi: rhoSin, rhoCosPhi: rhoCos, lon: lon,
                                      tNear: tMax, cone: .umbra, sign: -1) {
                contacts[.c2] = tdtToDate(midnightUTC: midnight, eclipse: eclipse, tTDT: tC2)
            }
            if let tC3 = findContact(eclipse: eclipse,
                                      rhoSinPhi: rhoSin, rhoCosPhi: rhoCos, lon: lon,
                                      tNear: tMax, cone: .umbra, sign: +1) {
                contacts[.c3] = tdtToDate(midnightUTC: midnight, eclipse: eclipse, tTDT: tC3)
            }
        }

        // Magnitud del eclipse en el máximo.
        // Denominador = l1Obs + l2Obs = 2·R_Sol (siempre, independiente del signo de l2Obs).
        // Para totales (l2Obs < 0) el resultado excede 1.0, conforme al estándar Espenak/NASA.
        // Ref: Espenak & Meeus (2009), NASA TP-2009-214174, §Eclipse Magnitude.
        let magnitude = (l1Obs - deltaMax) / (l1Obs + l2Obs)

        // Fracción del área del disco solar cubierta por la Luna en el máximo.
        let obscuration = solarObscuration(kind: kind, deltaMax: deltaMax,
                                            l1Obs: l1Obs, l2Obs: l2Obs)

        // Altitud y azimut solar en el máximo.
        let (altitude, azimuth) = sunAltAz(
            latDeg: lat,
            declinationDeg: elMax.d,
            hourAngleDeg: elMax.mu + lon
        )

        // Si el Sol está bajo el horizonte en el máximo el eclipse no es observable.
        // Ocurre cuando la penumbra alcanza geométricamente puntos en noche local
        // (ej. Tokio durante el eclipse del 12/08/2026, que ocurre a las 01:00 JST).
        guard altitude > 0 else { return nil }

        // Duración de la totalidad o anularidad.
        let totalityDuration: Double?
        if kind != .partial, let c2 = contacts[.c2], let c3 = contacts[.c3] {
            totalityDuration = c3.timeIntervalSince(c2)
        } else {
            totalityDuration = nil
        }

        return EclipseCircumstances(
            kind: kind,
            contacts: contacts,
            magnitude: magnitude,
            sunAltitudeAtMax: altitude,
            sunAzimuthAtMax: azimuth,
            obscuration: obscuration,
            totalityDurationSeconds: totalityDuration
        )
    }

    // MARK: - Solar obscuration

    /// Computes the fraction of the solar disk area covered by the Moon at maximum eclipse.
    ///
    /// Uses the standard circle-intersection formula for partial eclipses.
    /// For total eclipses the result is exactly 1.0; for annular/hybrid it is k²
    /// (the full lunar disk is inside the solar disk at maximum).
    ///
    /// The lunar/solar radius ratio k and normalized center-to-center separation d
    /// are derived from the Besselian cone radii at the observer's level:
    ///
    /// - For annular geometry (l2Obs ≥ 0):  2·R☉ = l1Obs + |l2Obs|, k < 1
    /// - For total geometry  (l2Obs < 0):   2·R☉ = l1Obs − |l2Obs|, k > 1
    ///
    /// Circle-intersection area (r₁ = 1, r₂ = k, separation d):
    /// ```
    /// A = arccos((d²+1−k²)/2d) + k²·arccos((d²+k²−1)/2dk) − ½·√s
    /// where s = (1+k+d)(1+k−d)(d+k−1)(d−k+1)
    /// obscuration = A / π
    /// ```
    ///
    /// Ref: Espenak, F. & Meeus, J. (2009). *Five Millennium Canon of Solar Eclipses*.
    /// NASA TP-2009-214174, eclipse circumstance formulae.
    ///
    /// - Parameters:
    ///   - kind: Eclipse type at the observer's location.
    ///   - deltaMax: Distance from observer to shadow axis on the fundamental plane.
    ///   - l1Obs: Penumbral cone radius at the observer's level.
    ///   - l2Obs: Umbral/antumbral cone radius (negative for total-type geometry).
    /// - Returns: Obscuration fraction in [0, 1], or `nil` for simulated eclipses.
    private static func solarObscuration(kind: EclipseKind, deltaMax: Double,
                                          l1Obs: Double, l2Obs: Double) -> Double? {
        let absL2 = abs(l2Obs)

        switch kind {
        case .total:
            // El disco solar está completamente cubierto.
            return 1.0

        case .annular, .hybrid:
            // La Luna cruza el disco solar completamente; área cubierta = π·R☉²·k².
            // Para geometría anular: 2·R☉ = l1Obs + absL2
            let k = (l1Obs - absL2) / (l1Obs + absL2)
            return k * k

        case .partial:
            // Seleccionar la normalización según la geometría del eclipse.
            // Geometría anular (l2Obs ≥ 0): R☉ = (l1Obs + absL2)/2
            // Geometría total  (l2Obs < 0): R☉ = (l1Obs − absL2)/2
            let twoRsun: Double = l2Obs >= 0 ? l1Obs + absL2 : l1Obs - absL2
            guard twoRsun > 1e-9 else { return nil }

            let k: Double = l2Obs >= 0
                ? (l1Obs - absL2) / twoRsun   // geometría anular: k < 1
                : (l1Obs + absL2) / twoRsun   // geometría total:  k > 1
            let d = 2.0 * deltaMax / twoRsun  // separación en radios solares

            // Casos límite.
            if d >= 1.0 + k { return 0.0 }    // sin solapamiento (fuera de penumbra)
            if d + k <= 1.0 { return k * k }   // Luna completamente dentro del Sol
            if d + 1.0 <= k { return 1.0 }     // Sol completamente dentro de la Luna

            // Fórmula general de intersección de dos círculos: r₁ = 1, r₂ = k, sep. = d.
            // Ref: Meeus (1998), appendix; Espenak (2009).
            let cosAlpha = (d * d + 1.0 - k * k) / (2.0 * d)
            let cosBeta  = (d * d + k * k - 1.0) / (2.0 * d * k)

            // Clamp para evitar errores numéricos en los bordes del eclipse.
            let alpha = acos(max(-1.0, min(1.0, cosAlpha)))
            let beta  = acos(max(-1.0, min(1.0, cosBeta)))

            let s = (1.0 + k + d) * (1.0 + k - d) * (d + k - 1.0) * (d - k + 1.0)
            guard s >= 0.0 else { return nil }

            let area = alpha + k * k * beta - 0.5 * sqrt(s)
            return max(0.0, min(1.0, area / .pi))

        case .simulated:
            return nil
        }
    }

    // MARK: - Finding maximum eclipse

    /// Finds the time t (TDT hours from t0) of the local maximum eclipse using Newton-Raphson.
    ///
    /// Solves d(Δ²)/dt = 2(U·U′ + V·V′) = 0, where Δ is the distance from the
    /// observer to the shadow axis on the fundamental plane.
    /// Starting from t = 0, convergence is typically achieved in ≤ 5 iterations.
    ///
    /// Ref: Meeus (1998), p. 379, "Minimum Distance".
    private static func findMaximum(eclipse: BesselianEclipse,
                                     rhoSinPhi: Double, rhoCosPhi: Double,
                                     lon: Double) -> Double {
        var t = 0.0
        for _ in 0..<50 {
            let el  = elements(eclipse: eclipse, t: t)
            let obs = observerFP(rhoSinPhi: rhoSinPhi, rhoCosPhi: rhoCosPhi,
                                 lon: lon, el: el)

            let U  = el.x - obs.xi
            let V  = el.y - obs.eta
            let Up = el.dx - obs.dxi
            let Vp = el.dy - obs.deta

            let denom = Up * Up + Vp * Vp
            guard denom > 1e-15 else { break }

            let step = -(U * Up + V * Vp) / denom
            t += step
            if abs(step) < 1e-6 { break }   // convergido a < 0.0036 s
        }
        return t
    }

    // MARK: - Finding contact times

    private enum Cone { case penumbra, umbra }

    /// Shadow function: positive when the observer is outside the given cone,
    /// negative when inside, zero at the moment of contact.
    private static func shadowF(eclipse: BesselianEclipse,
                                 rhoSinPhi: Double, rhoCosPhi: Double,
                                 lon: Double, t: Double, cone: Cone) -> Double {
        let el  = elements(eclipse: eclipse, t: t)
        let obs = observerFP(rhoSinPhi: rhoSinPhi, rhoCosPhi: rhoCosPhi,
                             lon: lon, el: el)
        let U     = el.x - obs.xi
        let V     = el.y - obs.eta
        let delta = sqrt(U * U + V * V)
        switch cone {
        case .penumbra:
            return delta - (el.l1 - obs.zeta * eclipse.tan_f1)
        case .umbra:
            return delta - abs(el.l2 - obs.zeta * eclipse.tan_f2)
        }
    }

    /// First derivative of the shadow function with respect to t.
    private static func shadowDF(eclipse: BesselianEclipse,
                                  rhoSinPhi: Double, rhoCosPhi: Double,
                                  lon: Double, t: Double, cone: Cone) -> Double {
        let el  = elements(eclipse: eclipse, t: t)
        let obs = observerFP(rhoSinPhi: rhoSinPhi, rhoCosPhi: rhoCosPhi,
                             lon: lon, el: el)
        let U  = el.x - obs.xi
        let V  = el.y - obs.eta
        let Up = el.dx - obs.dxi
        let Vp = el.dy - obs.deta
        let delta = sqrt(U * U + V * V)
        guard delta > 1e-9 else { return 0 }
        let dDelta = (U * Up + V * Vp) / delta
        switch cone {
        case .penumbra:
            return dDelta - el.dl1
        case .umbra:
            // Signo de la derivada de |l2obs| depende del signo de l2 (negativo en total).
            return dDelta - (el.l2 < 0 ? -el.dl2 : el.dl2)
        }
    }

    /// Finds the time of a shadow contact using a coarse scan followed by Newton-Raphson.
    ///
    /// Scans outward from `tNear` in direction `sign`, detecting the sign change of the
    /// shadow function, then refines with Newton-Raphson to sub-millisecond precision.
    ///
    /// - Parameters:
    ///   - tNear: Reference time (local maximum), TDT hours from t0.
    ///   - cone: Which shadow cone to test: penumbra (C1/C4) or umbra (C2/C3).
    ///   - sign: −1 to search before the maximum (C1, C2); +1 for after (C3, C4).
    /// - Returns: Contact time in TDT hours from t0, or `nil` if no contact is found
    ///   within 3 hours of the maximum.
    private static func findContact(eclipse: BesselianEclipse,
                                     rhoSinPhi: Double, rhoCosPhi: Double,
                                     lon: Double, tNear: Double,
                                     cone: Cone, sign: Double) -> Double? {
        // Paso de escaneo: 3 min para penumbra, 36 s para umbra (cubre totalidades cortas).
        let step  = sign * (cone == .penumbra ? 0.05 : 0.01)
        let limit = tNear + sign * 3.0

        var tPrev = tNear
        var fPrev = shadowF(eclipse: eclipse, rhoSinPhi: rhoSinPhi, rhoCosPhi: rhoCosPhi,
                            lon: lon, t: tPrev, cone: cone)

        var t = tNear + step
        while (sign > 0) ? t <= limit : t >= limit {
            let f = shadowF(eclipse: eclipse, rhoSinPhi: rhoSinPhi, rhoCosPhi: rhoCosPhi,
                            lon: lon, t: t, cone: cone)

            // Cambio de signo detectado: refinar con Newton-Raphson.
            if fPrev * f <= 0 {
                var tRef = (tPrev + t) / 2.0
                for _ in 0..<50 {
                    let fRef  = shadowF(eclipse: eclipse,
                                        rhoSinPhi: rhoSinPhi, rhoCosPhi: rhoCosPhi,
                                        lon: lon, t: tRef, cone: cone)
                    let dfRef = shadowDF(eclipse: eclipse,
                                         rhoSinPhi: rhoSinPhi, rhoCosPhi: rhoCosPhi,
                                         lon: lon, t: tRef, cone: cone)
                    guard abs(dfRef) > 1e-15 else { break }
                    let delta = -fRef / dfRef
                    tRef += delta
                    if abs(delta) < 1e-6 { break }
                }
                return tRef
            }

            tPrev = t
            fPrev = f
            t += step
        }
        return nil
    }

    // MARK: - Time conversion

    /// Converts a TDT time (hours from t0) to a UTC `Date`.
    ///
    /// Derivation:
    ///   - Absolute TDT = midnight_TDT + (t0_tdt_hours + t) · 3600 s
    ///   - UTC = TDT − ΔT
    ///   - UTC seconds from midnight_UTC = (t0_tdt_hours + t) · 3600 − ΔT
    ///
    /// - Parameters:
    ///   - midnightUTC: Midnight UTC of the eclipse day, pre-parsed at dataset load time.
    ///   - eclipse: Eclipse entry providing the reference time and ΔT.
    ///   - tTDT: Time offset in TDT hours from t0.
    /// - Returns: UTC `Date` for that instant.
    private static func tdtToDate(midnightUTC: Date,
                                  eclipse: BesselianEclipse,
                                  tTDT: Double) -> Date {
        let utcSeconds = (eclipse.t0_tdt_hours + tTDT) * 3600.0 - eclipse.delta_t_seconds
        return midnightUTC.addingTimeInterval(utcSeconds)
    }

    // MARK: - Solar position

    /// Computes solar altitude and azimuth using the observer's geographic coordinates,
    /// the solar declination, and the local hour angle.
    ///
    /// Implements the standard spherical-astronomy formulae:
    ///   Meeus (1998), chapter 13, equations (13.5)–(13.6).
    ///
    /// - Parameters:
    ///   - latDeg: Observer latitude in degrees.
    ///   - declinationDeg: Solar declination d(t) in degrees.
    ///   - hourAngleDeg: Local solar hour angle H = μ(t) + lon (East-positive), in degrees.
    /// - Returns: Tuple (altitude, azimuth) in degrees.
    ///   Altitude is measured above the horizon (positive up).
    ///   Azimuth is measured from North, clockwise (0° = N, 90° = E).
    private static func sunAltAz(latDeg: Double, declinationDeg: Double,
                                  hourAngleDeg: Double) -> (altitude: Double, azimuth: Double) {
        let φ = latDeg          * .pi / 180.0
        let δ = declinationDeg  * .pi / 180.0
        let H = hourAngleDeg    * .pi / 180.0

        let sinAlt   = sin(φ) * sin(δ) + cos(φ) * cos(δ) * cos(H)
        let altitude = asin(max(-1, min(1, sinAlt))) * 180.0 / .pi

        // Azimut medido desde el Norte, sentido horario.
        let azRad  = atan2(sin(H), cos(H) * sin(φ) - tan(δ) * cos(φ))
        let azimuth = (azRad * 180.0 / .pi + 180.0).truncatingRemainder(dividingBy: 360.0)

        return (altitude, azimuth)
    }
}
