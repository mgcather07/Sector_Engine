//
//  ConditionsResult.swift
//  Sector — Bowfishing Conditions Engine v2
//
//  The aggregator's output: the final score + band, the regime that shaped it,
//  a confidence signal, the per-factor breakdown (with the *active* weight that
//  varies by regime), any active gate caps, the "top reasons", and the
//  "where to look" cards. Pure value type — the UI renders it. §2.
//

import Foundation

/// One row in the breakdown sheet.
public struct FactorBreakdown: Equatable {
    public let key: FactorKey
    public let score: Int          // 0…100 sub-score
    public let weightPct: Int      // active (renormalized) weight, %
    public let label: String       // human value, e.g. "0.6 ft viz"
    public let why: String
}

/// An active veto/cap and why it fired.
public struct GateHit: Equatable {
    public let reason: String
    public let cap: Int
}

/// A "where to look" card. `kind` lets the UI pick an icon/tint; the engine
/// stays framework-free.
public struct WhereToLookCard: Equatable {
    public enum Kind: String, Equatable { case spawn, current, wind, level, clarity, darkness, temp }
    public let kind: Kind
    public let title: String
    public let body: String
}

public struct ConditionsResult: Equatable {
    public let score: Int
    public let band: ConditionsBand
    public let regime: ConditionsRegime

    public let confidence: Int
    public let confidenceBand: ConfidenceBand

    public let factors: [FactorBreakdown]
    public let gates: [GateHit]
    public let topReasons: [String]

    public let whereToLook: [WhereToLookCard]
    public let closingLine: String

    /// The leading spawn species (for copy/targeting), if any.
    public let spawnSpeciesName: String?
    public let spawnNeedsDisclaimer: Bool

    /// True if any gate capped the score.
    public var isCapped: Bool { !gates.isEmpty }
    /// The binding cap reason (lowest cap), if capped.
    public var primaryGate: GateHit? { gates.min { $0.cap < $1.cap } }
}
