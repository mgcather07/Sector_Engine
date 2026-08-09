//
//  SectorEngineAPI.swift
//  SectorEngine
//
//  The single PUBLIC entry point. Everything else in the module stays internal;
//  clients (the server, and eventually the app) call this and get a Codable
//  response. Same pipeline the app runs: snapshot → input → evaluate → forecast.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

/// The render-ready payload every client (iOS, Android, web) receives.
public struct ConditionsResponse: Codable, Equatable {
    public let score: Int
    public let band: String            // Poor | Fair | Good | Prime
    public let topReasons: [String]
    public let tonight: TonightDTO?
    public let nights: [NightDTO]
    public let generatedAt: Date
}

public struct TonightDTO: Codable, Equatable {
    public let headline: String        // "Peak 10:40 PM" / "Winding down" / …
    public let windowStart: Date?
    public let windowEnd: Date?
    public let peak: Date?
}

public struct NightDTO: Codable, Equatable {
    public let date: Date
    public let score: Int
    public let rating: String          // Poor | Fair | Good | Prime
    public let moonIllumination: Double // 0…1
    public let windMax: Double         // mph
    public let weatherCode: Int        // sanitized WMO
    public let precip: Double          // inches
}

public enum SectorEngineAPI {

    /// Score a coordinate for `date`: the gauge score + 7-night outlook + tonight's
    /// window. Returns nil when there's no live data to score (no weather + no gage).
    public static func conditions(lat: Double, lon: Double, date: Date = Date()) async -> ConditionsResponse? {
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        let snap = await ConditionsSnapshotProvider.shared.snapshot(for: coord)
        guard snap.hasAnyLiveInput else { return nil }

        let input = ConditionsInputBuilder.build(
            coordinate: coord, date: date,
            weather: snap.weather, water: snap.water, discharge: snap.discharge,
            waterTempC: snap.waterTemp, modeledWaterTempF: snap.waterTempModel?.currentF,
            turbidity: snap.turbidity, generation: snap.generation,
            alertWindFloorMph: snap.alertWindFloorMph)
        let result = ConditionsAggregator.evaluate(input)

        let forecast = await ConditionsForecastService.forecast(for: coord, now: date)
        let tonight = forecast?.tonight.map {
            TonightDTO(headline: $0.headline, windowStart: $0.windowStart,
                       windowEnd: $0.windowEnd, peak: $0.peak)
        }
        let nights = (forecast?.nights ?? []).map {
            NightDTO(date: $0.date, score: $0.score, rating: $0.rating.rawValue,
                     moonIllumination: $0.moonIllumination, windMax: $0.windMax,
                     weatherCode: $0.weatherCode, precip: $0.precip)
        }

        return ConditionsResponse(
            score: result.score, band: result.band.rawValue,
            topReasons: result.topReasons, tonight: tonight,
            nights: nights, generatedAt: Date())
    }
}
