//
//  MrmsPrecipService.swift
//  SectorEngine
//
//  Recent rainfall from NOAA MRMS (Multi-Radar Multi-Sensor QPE, radar+gauge),
//  read through the Iowa Environmental Mesonet IEMRE point API as plain JSON —
//  no GRIB2 to parse. Two reasons this replaces Open-Meteo for the clarity model:
//
//    1. MRMS is radar-gauge and ~1 km; it catches the localized convective rain
//       an ~11 km forecast model routinely reads as 0.0" (verified: Gardendale AL
//       showed 0.68" on a day Open-Meteo missed entirely).
//    2. We aggregate over the SURROUNDING watershed, not just the ramp — rain
//       upstream muddies the lake even when it stayed dry where you launch.
//
//  Returns nil on any failure so the caller falls back to the Open-Meteo 48 h
//  point total. IEMRE precip is itself MRMS-derived for recent dates.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CoreLocation

/// Rainfall the clarity model actually needs: a watershed-aggregated 72 h total,
/// plus the point's daily series for the sightline trend chart.
struct MrmsPrecip {
    let watershed72hIn: Double
    let point72hIn: Double
    let daily: [DailyRain]              // point, last ~14 days (oldest → newest)
    struct DailyRain { let date: Date; let inches: Double }
}

final class MrmsPrecipService {
    static let shared = MrmsPrecipService()
    private init() {}

    /// ~0.35° ≈ 24 mi in four directions — samples nearby cells that drain toward
    /// the same water without needing a flow-direction/HUC dataset.
    private let ringOffsetDeg = 0.35
    private let historyDays = 14

    func recent(near coordinate: CLLocationCoordinate2D, now: Date = Date()) async -> MrmsPrecip? {
        let lat = coordinate.latitude, lon = coordinate.longitude
        async let pt = daily(lat: lat, lon: lon, days: historyDays, now: now)
        // Four surrounding samples for the watershed signal.
        let d = ringOffsetDeg
        async let n = last72(lat: lat + d, lon: lon, now: now)
        async let s = last72(lat: lat - d, lon: lon, now: now)
        async let e = last72(lat: lat, lon: lon + d, now: now)
        async let w = last72(lat: lat, lon: lon - d, now: now)

        guard let ptDaily = await pt, !ptDaily.isEmpty else { return nil }
        let point72 = ptDaily.suffix(3).reduce(0) { $0 + $1.inches }
        let ring = [await n, await s, await e, await w].compactMap { $0 }
        let ringMax = ring.max() ?? 0
        let ringMean = ring.isEmpty ? 0 : ring.reduce(0, +) / Double(ring.count)
        // Surrounding rain that reaches the lake counts even if the ramp was dry:
        // take the strongest nearby cell (dampened) or the ring mean, but never
        // less than the point itself.
        let watershed = Swift.max(point72, 0.7 * ringMax, ringMean)
        return MrmsPrecip(watershed72hIn: watershed, point72hIn: point72, daily: ptDaily)
    }

    private func last72(lat: Double, lon: Double, now: Date) async -> Double? {
        guard let d = await daily(lat: lat, lon: lon, days: 4, now: now) else { return nil }
        return d.suffix(3).reduce(0) { $0 + $1.inches }
    }

    private struct IEMREResponse: Decodable {
        let data: [Day]
        struct Day: Decodable { let date: String; let mrms_precip_in: Double? }
    }

    /// Daily MRMS precip (inches) at a point for the last `days`, dropping days the
    /// reanalysis hasn't filled yet (most-recent day is often null).
    private func daily(lat: Double, lon: Double, days: Int, now: Date) async -> [MrmsPrecip.DailyRain]? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: now) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let s = fmt.string(from: start), e = fmt.string(from: now)
        let path = "https://mesonet.agron.iastate.edu/iemre/multiday/\(s)/\(e)/\(String(format: "%.4f", lat))/\(String(format: "%.4f", lon))/json"
        guard let url = URL(string: path) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(IEMREResponse.self, from: data) else { return nil }
        return decoded.data.compactMap { day -> MrmsPrecip.DailyRain? in
            guard let inches = day.mrms_precip_in, let dt = fmt.date(from: day.date) else { return nil }
            return MrmsPrecip.DailyRain(date: dt, inches: Swift.max(0, inches))
        }
    }
}
