//
//  LakeDirectorySearch.swift
//  Sector — ranked lookup over the curated lake directory
//
//  The matching that makes the curated list usable: name-normalized (so
//  "Lake Guntersville", "Guntersville Lake" and "guntersville" all hit the
//  entry stored as "Guntersville"), ranked exact → prefix → substring → all
//  tokens, and broken ties by nearness to the user. Fast enough to run on every
//  keystroke over 620 lakes — it's an in-memory scan, no network.
//

import Foundation
import CoreLocation

extension LakeDirectory {

    /// Ranked directory matches for a free-text query, nearest first within a
    /// rank tier. Empty when nothing matches (the caller then falls back to
    /// MapKit for the long tail).
    static func search(_ query: String, near: CLLocationCoordinate2D?, limit: Int = 25) -> [DirectoryLake] {
        let q = normalize(query)
        guard q.count >= 2 else { return [] }
        let qTokens = q.split(separator: " ").map(String.init)

        var scored: [(lake: DirectoryLake, score: Double)] = []
        for lake in all {
            let n = normalize(lake.name)
            let rank: Double
            if n == q { rank = 0 }
            else if n.hasPrefix(q) { rank = 1 }
            else if n.contains(q) { rank = 2 }
            else if qTokens.allSatisfy({ n.contains($0) }) { rank = 3 }
            else { continue }
            // Distance (miles) is the tie-break inside a rank tier, so a nearby
            // "Wheeler" outranks one three states away.
            let dist = near.map { miles($0, lake.coordinate) } ?? 0
            scored.append((lake, rank * 100_000 + dist))
        }
        return scored.sorted { $0.score < $1.score }.prefix(limit).map(\.lake)
    }

    /// Lowercase, strip accents and punctuation, drop the water words people add
    /// inconsistently ("lake", "reservoir", "pond") and articles — so the query
    /// and the stored name meet in the middle.
    static func normalize(_ s: String) -> String {
        let folded = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        var cleaned = ""
        for ch in folded { cleaned.append(ch.isLetter || ch.isNumber ? ch : " ") }
        let stop: Set<String> = ["lake", "lakes", "reservoir", "res", "pond", "the", "of"]
        return cleaned.split(separator: " ").map(String.init)
            .filter { !stop.contains($0) }
            .joined(separator: " ")
    }

    static func miles(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1609.34
    }

    /// Full state name for a two-letter code, for the search-row subtitle.
    static func stateName(_ code: String) -> String { stateNames[code] ?? code }

    /// Subtitle for a directory row — abbreviations only, primary state first:
    /// "AL", or "TN · AL · MS" for a border reservoir. Spelled-out names made
    /// multi-state rows long and mixed two registers in one line.
    static func statesLabel(_ lake: DirectoryLake) -> String {
        lake.states.joined(separator: " · ")
    }

    /// Nearest directory entry to a coordinate. Used to look up a dam's routing
    /// (which CWMS office owns it) without depending on name spelling — an
    /// operator calls it "Bull Shoals Dam" where the sheet says "Bull Shoals
    /// Lake", and CWMS calls Lake Lanier's project "Buford".
    static func nearest(to coordinate: CLLocationCoordinate2D,
                        withinMiles: Double = 12) -> DirectoryLake? {
        all.map { ($0, miles(coordinate, $0.coordinate)) }
            .filter { $0.1 <= withinMiles }
            .min { $0.1 < $1.1 }?.0
    }

    /// The directory entry a saved lake refers to, if any: normalized-name match
    /// within `withinMiles`. Lets stored rows pick up naming fixes without a
    /// data migration.
    static func match(name: String, coordinate: CLLocationCoordinate2D,
                      withinMiles: Double = 30) -> DirectoryLake? {
        let n = normalize(name)
        guard !n.isEmpty else { return nil }
        return all
            .filter { normalize($0.name) == n }
            .map { ($0, miles(coordinate, $0.coordinate)) }
            .filter { $0.1 <= withinMiles }
            .min { $0.1 < $1.1 }?.0
    }

    private static let stateNames: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
        "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
        "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
        "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah",
        "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
        "WI": "Wisconsin", "WY": "Wyoming", "DC": "Washington, DC",
    ]
}
