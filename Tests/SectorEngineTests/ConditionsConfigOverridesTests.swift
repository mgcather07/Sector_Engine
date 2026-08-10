//
//  ConditionsConfigOverridesTests.swift
//  SectorEngineTests
//
//  Phase 6 Stage 4: prove a Remote Config `conditions_config` JSON blob decodes and
//  applies onto the compiled defaults — the offline validation of the tuning path
//  (the live Remote Config fetch itself only runs on Cloud Run).
//

import XCTest
@testable import SectorEngine

final class ConditionsConfigOverridesTests: XCTestCase {

    func testDecodesAndApplies() throws {
        let json = """
        {
          "weightsNormal": { "wind": 0.30, "clarity": 0.10 },
          "spawnRegimeThreshold": 55,
          "clarityEstimatedScoreCap": 85,
          "darknessAstroDarkBonus": 8,
          "seeabilityEnabled": false
        }
        """
        let ov = try JSONDecoder().decode(ConditionsConfigOverrides.self, from: Data(json.utf8))
        let c = ov.apply(to: .default)

        // Overridden knobs take the new values...
        XCTAssertEqual(c.weights.normal.wind, 0.30)
        XCTAssertEqual(c.weights.normal.clarity, 0.10)
        XCTAssertEqual(c.spawn.regimeThreshold, 55)
        XCTAssertEqual(c.clarity.estimatedScoreCap, 85)
        XCTAssertEqual(c.darkness.astroDarkBonus, 8)
        XCTAssertFalse(c.seeability.enabled)

        // ...and factors NOT named in the override keep their defaults.
        XCTAssertEqual(c.weights.normal.darkness, ConditionsConfig.default.weights.normal.darkness)
        XCTAssertEqual(c.weights.spawn.spawn, ConditionsConfig.default.weights.spawn.spawn)
    }

    func testEmptyOverridesAreIdentity() throws {
        let ov = try JSONDecoder().decode(ConditionsConfigOverrides.self, from: Data("{}".utf8))
        let c = ov.apply(to: .default)
        XCTAssertEqual(c.spawn.regimeThreshold, ConditionsConfig.default.spawn.regimeThreshold)
        XCTAssertEqual(c.weights.normal.wind, ConditionsConfig.default.weights.normal.wind)
        XCTAssertEqual(c.clarity.estimatedScoreCap, ConditionsConfig.default.clarity.estimatedScoreCap)
    }
}
