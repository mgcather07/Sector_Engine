//
//  SectorEngineAPI.swift
//  SectorEngine
//
//  The single PUBLIC entry point. Everything else in the module stays internal;
//  clients (the server, iOS, Android, web) call this and get a Codable response.
//  Same pipeline the app runs: snapshot → input → evaluate → forecast.
//
//  Phase 6: the response is the FULL render payload — the computed result
//  (score, band, per-factor breakdown, gates, where-to-look), the tonight window
//  with its hourly curve, the 7-night outlook with per-night breakdowns, AND the
//  raw live readings (weather, water, generation, alerts, moon) the clients still
//  compose their tiles and window-sheet guidance from. Clients keep only
//  presentation (icons, tints, tier words, moon graphics, prose, timezone-local
//  formatting) and the ephemeris; the scoring + fetching live here.
//
//  Back-compat: this is a strict SUPERSET of the Phase 4/5 payload — every field
//  those clients decode (score, band, topReasons, tonight{headline,windowStart,
//  windowEnd,peak}, nights[{date,score,rating,moonIllumination,windMax,
//  weatherCode,precip}]) keeps its exact name and shape. New fields are additive;
//  decoders ignore what they don't know.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - Response

/// The render-ready payload every client (iOS, Android, web) receives.
public struct ConditionsResponse: Codable, Equatable {
    // Headline + breakdown (from ConditionsResult)
    public let score: Int
    public let band: String            // Poor | Fair | Good | Prime
    public let regime: String          // normal | spawn | tailwater
    public let confidence: Int
    public let confidenceBand: String  // Low | Med | High
    public let topReasons: [String]
    public let closingLine: String
    public let spawnSpeciesName: String?
    public let spawnNeedsDisclaimer: Bool
    public let factors: [FactorDTO]
    public let gates: [GateDTO]
    public let whereToLook: [WhereToLookDTO]

    // Live readings for the tiles + window-sheet guidance (from the snapshot)
    public let weather: WeatherDTO?
    public let water: WaterDTO?         // gage height / level
    public let discharge: WaterDTO?     // cfs
    public let generation: GenerationDTO?
    public let moonIllumination: Double // 0…1, for "now"
    public let alerts: [AlertDTO]

    // Tonight window + 7-night outlook
    public let tonight: TonightDTO?
    public let nights: [NightDTO]

    public let generatedAt: Date
}

// MARK: - Breakdown DTOs

public struct FactorDTO: Codable, Equatable {
    public let key: String        // FactorKey rawValue: clarity|spawn|darkness|wind|waterTemp|level|current|pressure|sky|humidity
    public let score: Int         // 0…100 sub-score
    public let weightPct: Int     // active (renormalized) weight, %
    public let label: String      // human value, e.g. "0.6 ft viz"
    public let why: String
}

public struct GateDTO: Codable, Equatable {
    public let reason: String
    public let cap: Int
}

public struct WhereToLookDTO: Codable, Equatable {
    public let kind: String       // spawn|current|wind|level|clarity|darkness|temp
    public let title: String
    public let body: String
}

// MARK: - Live reading DTOs

public struct WeatherDTO: Codable, Equatable {
    public let temperature: Double        // °F
    public let conditionDescription: String
    public let conditionSymbol: String    // SF Symbol name (iOS renders; Android maps)
    public let windSpeed: Double          // mph
    public let windDirection: Int         // degrees, 0 = N
    public let precipitation: Double      // inches, now
    public let recentRainfall: Double     // inches, past ~3 days
    public let humidity: Int              // %
    public let pressure: Double           // hPa
    public let pressureTrend: String      // rising | falling | steady
    public let pressureChange: Double     // signed hPa over the lookback
    public let cloudCover: Double         // %
    public let weatherCode: Int           // WMO
}

public struct WaterDTO: Codable, Equatable {
    public let value: Double
    public let unit: String
    public let trend: String              // rising | falling | steady
    public let change: Double             // signed, in `unit`
    public let history: [Double]          // oldest → newest, for a sparkline
}

public struct GenerationDTO: Codable, Equatable {
    public let damName: String
    public let river: String
    public let distanceMiles: Double
    public let dischargeCfs: Double?
    public let dischargeTrend12hCfs: Double?
    public let reservoirElevationFt: Double?
    public let tailwaterElevationFt: Double?
    public let observedAt: Date?
    public let windows: [GenerationWindowDTO]

    public struct GenerationWindowDTO: Codable, Equatable {
        public let start: Date
        public let end: Date
        public let generators: Int
        public let isMinimum: Bool
        public let unitsAreDerived: Bool
        public let timeZoneIdentifier: String   // the DAM's zone; clients format in it
    }
}

public struct AlertDTO: Codable, Equatable {
    public let id: String
    public let event: String
    public let severity: String           // extreme | severe | moderate | minor | unknown
    public let headline: String
    public let details: String
    public let ends: Date?
}

// MARK: - Forecast DTOs

public struct TonightDTO: Codable, Equatable {
    public let headline: String           // kept for back-compat; new clients derive from timestamps in device tz
    public let windowStart: Date?
    public let windowEnd: Date?
    public let peak: Date?
    public let sunset: Date?
    public let sunrise: Date?
    public let displayStart: Date?
    public let displayEnd: Date?
    public let hours: [HourDTO]            // the chart curve, 6 PM → 6 AM

    public struct HourDTO: Codable, Equatable {
        public let date: Date
        public let score: Int
    }
}

public struct NightDTO: Codable, Equatable {
    public let date: Date
    public let score: Int
    public let rating: String             // Poor | Fair | Good | Prime
    public let moonIllumination: Double
    public let windMax: Double            // mph
    public let weatherCode: Int
    public let precip: Double             // inches
    public let confidence: Int
    public let regime: String
    public let topReasons: [String]
    public let factors: [NightFactorDTO]

    public struct NightFactorDTO: Codable, Equatable {
        public let key: String            // FactorKey rawValue (forecast vocabulary)
        public let detail: String         // human value, e.g. "74% lit"
        public let sub: Int               // 0…100
        public let weight: Int            // active regime weight, %
    }
}

// MARK: - Entry point

public enum SectorEngineAPI {

    /// Score a coordinate for `date`: the gauge score + full breakdown + 7-night
    /// outlook + tonight's window + the live readings for the tiles. Returns nil
    /// when there's no live data to score (no weather + no gage).
    public static func conditions(lat: Double, lon: Double, date: Date = Date()) async -> ConditionsResponse? {
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        // Fire the gauge snapshot and the 7-night forecast concurrently — they're
        // independent, and the forecast's own snapshot fetch coalesces onto this
        // one inside the provider, so nothing is fetched twice.
        async let snapTask = ConditionsSnapshotProvider.shared.snapshot(for: coord)
        async let forecastTask = ConditionsForecastService.forecast(for: coord, now: date)

        let snap = await snapTask
        guard snap.hasAnyLiveInput else { return nil }

        let input = ConditionsInputBuilder.build(
            coordinate: coord, date: date,
            weather: snap.weather, water: snap.water, discharge: snap.discharge,
            waterTempC: snap.waterTemp, modeledWaterTempF: snap.waterTempModel?.currentF,
            turbidity: snap.turbidity, generation: snap.generation,
            alertWindFloorMph: snap.alertWindFloorMph)
        let result = ConditionsAggregator.evaluate(input)

        let forecast = await forecastTask

        return ConditionsResponse(
            score: result.score,
            band: result.band.rawValue,
            regime: result.regime.rawValue,
            confidence: result.confidence,
            confidenceBand: result.confidenceBand.rawValue,
            topReasons: result.topReasons,
            closingLine: result.closingLine,
            spawnSpeciesName: result.spawnSpeciesName,
            spawnNeedsDisclaimer: result.spawnNeedsDisclaimer,
            factors: result.factors.map {
                FactorDTO(key: $0.key.rawValue, score: $0.score,
                          weightPct: $0.weightPct, label: $0.label, why: $0.why)
            },
            gates: result.gates.map { GateDTO(reason: $0.reason, cap: $0.cap) },
            whereToLook: result.whereToLook.map {
                WhereToLookDTO(kind: $0.kind.rawValue, title: $0.title, body: $0.body)
            },
            weather: snap.weather.map(Self.weatherDTO),
            water: snap.water.map(Self.waterDTO),
            discharge: snap.discharge.map(Self.waterDTO),
            generation: snap.generation.map(Self.generationDTO),
            moonIllumination: Astronomy.moonIllumination(on: date),
            alerts: snap.alerts.map(Self.alertDTO),
            tonight: forecast?.tonight.map(Self.tonightDTO),
            nights: (forecast?.nights ?? []).map(Self.nightDTO),
            generatedAt: Date())
    }

    // MARK: Mappers

    private static func weatherDTO(_ w: WeatherReading) -> WeatherDTO {
        WeatherDTO(
            temperature: w.temperature, conditionDescription: w.conditionDescription,
            conditionSymbol: w.conditionSymbol, windSpeed: w.windSpeed,
            windDirection: w.windDirection, precipitation: w.precipitation,
            recentRainfall: w.recentRainfall, humidity: w.humidity,
            pressure: w.pressure, pressureTrend: pressureTrendString(w.pressureTrend),
            pressureChange: w.pressureChange, cloudCover: w.cloudCover, weatherCode: w.weatherCode)
    }

    private static func waterDTO(_ r: WaterLevelReading) -> WaterDTO {
        WaterDTO(value: r.value, unit: r.unit, trend: waterTrendString(r.trend),
                 change: r.change, history: r.history)
    }

    private static func generationDTO(_ g: DamGeneration) -> GenerationDTO {
        GenerationDTO(
            damName: g.dam.name, river: g.dam.river, distanceMiles: g.distanceMiles,
            dischargeCfs: g.dischargeCfs, dischargeTrend12hCfs: g.dischargeTrend12hCfs,
            reservoirElevationFt: g.reservoirElevationFt, tailwaterElevationFt: g.tailwaterElevationFt,
            observedAt: g.observedAt,
            windows: g.windows.map {
                GenerationDTO.GenerationWindowDTO(
                    start: $0.start, end: $0.end, generators: $0.generators,
                    isMinimum: $0.isMinimum, unitsAreDerived: $0.unitsAreDerived,
                    timeZoneIdentifier: $0.timeZone.identifier)
            })
    }

    private static func alertDTO(_ a: WeatherAlert) -> AlertDTO {
        AlertDTO(id: a.id, event: a.event, severity: severityString(a.severity),
                 headline: a.headline, details: a.details, ends: a.ends)
    }

    private static func tonightDTO(_ t: TonightWindow) -> TonightDTO {
        TonightDTO(
            headline: t.headline, windowStart: t.windowStart, windowEnd: t.windowEnd,
            peak: t.peak, sunset: t.sunset, sunrise: t.sunrise,
            displayStart: t.displayStart, displayEnd: t.displayEnd,
            hours: t.hours.map { TonightDTO.HourDTO(date: $0.date, score: $0.score) })
    }

    private static func nightDTO(_ n: NightScore) -> NightDTO {
        NightDTO(
            date: n.date, score: n.score, rating: n.rating.rawValue,
            moonIllumination: n.moonIllumination, windMax: n.windMax,
            weatherCode: n.weatherCode, precip: n.precip, confidence: n.confidence,
            regime: n.regime.rawValue, topReasons: n.topReasons,
            factors: n.factors.map {
                NightDTO.NightFactorDTO(key: $0.key, detail: $0.detail, sub: $0.sub, weight: $0.weight)
            })
    }

    private static func pressureTrendString(_ t: PressureTrend) -> String {
        switch t { case .rising: return "rising"; case .falling: return "falling"; case .steady: return "steady" }
    }
    private static func waterTrendString(_ t: WaterTrend) -> String {
        switch t { case .rising: return "rising"; case .falling: return "falling"; case .steady: return "steady" }
    }
    private static func severityString(_ s: AlertSeverity) -> String {
        switch s {
        case .extreme: return "extreme"; case .severe: return "severe"
        case .moderate: return "moderate"; case .minor: return "minor"; case .unknown: return "unknown"
        }
    }
}
