//
//  CoreLocationShim.swift
//  SectorEngine
//
//  CoreLocation is Apple-only; Linux (the Cloud Run server) has no such module.
//  This provides the minimal surface the engine actually uses — a lat/lon pair and
//  a great-circle distance — so the exact same engine code compiles on both. On
//  Apple platforms this file is inert and the real CoreLocation types are used.
//

#if !canImport(CoreLocation)
import Foundation

public typealias CLLocationDegrees = Double
public typealias CLLocationDistance = Double

public struct CLLocationCoordinate2D: Sendable {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees
    public init(latitude: CLLocationDegrees = 0, longitude: CLLocationDegrees = 0) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public final class CLLocation: @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Great-circle distance in meters (haversine) — matches `CLLocation.distance(from:)`.
    public func distance(from other: CLLocation) -> CLLocationDistance {
        let earthRadius = 6_371_000.0
        let lat1 = coordinate.latitude * .pi / 180
        let lat2 = other.coordinate.latitude * .pi / 180
        let dLat = (other.coordinate.latitude - coordinate.latitude) * .pi / 180
        let dLon = (other.coordinate.longitude - coordinate.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
#endif
