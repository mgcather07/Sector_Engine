//
//  Coordinate.swift
//  Sector
//
//  Created by Michael Cather on 4/19/24.
//

import Foundation
#if canImport(MapKit)
import MapKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

struct Coordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    
    init(
        latitude: Double = 0.0,
        longitude: Double = 0.0
    ) {
        self.latitude = latitude
        self.longitude = longitude
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> Coordinate? {
        guard let latitude = dict["latitude"] as? Double,
              let longitude = dict["longitude"] as? Double else {
            return nil
        }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
    
    // **Added Initializer for CLLocation**
    init(location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
    }
}
