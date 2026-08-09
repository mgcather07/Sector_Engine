//
//  ConditionsGates.swift
//  Sector — Bowfishing Conditions Engine v2
//
//  Gates / vetoes (§6). A great score on a night you literally can't fish
//  destroys trust, so these hard caps are applied AFTER the weighted blend and
//  cap the final score regardless of how good the other factors look. The
//  binding gate is surfaced as the top "why".
//

import Foundation

public enum ConditionsGates {

    public static func evaluate(_ input: ConditionsInput,
                                config: ConditionsConfig = .default,
                                generationLevel: GenerationLevel?) -> [GateHit] {
        let g = config.gates
        var hits: [GateHit] = []

        let vis = ClarityFactor.visibilityFt(input, config: config)
        if vis < g.blownOutVisibilityFt {
            hits.append(GateHit(reason: "Water blown out — \(String(format: "%.1f", vis)) ft visibility",
                                cap: Int(g.blownOutCap)))
        }
        if input.windMph > g.highWindMph {
            hits.append(GateHit(reason: "High wind — \(Int(input.windMph.rounded())) mph",
                                cap: Int(g.highWindCap)))
        }
        if input.isTailwater, generationLevel == .high {
            hits.append(GateHit(reason: "Heavy dam generation across the window",
                                cap: Int(g.tailwaterHighGenCap)))
        }
        // Cold water pushes rough fish deep and inactive — nothing shallow to
        // shoot. A LIVE gage caps hard at the real threshold. A gage-less lake
        // scores off a MODELED/air estimate, so it gets its own COLDER trigger and
        // a SOFTER cap: a guess shouldn't hard-cap a night, but a clearly-cold
        // estimate must not read Prime (the old live-only gate let a 40°F winter
        // night blend to green on the many lakes with no temp gage). §6.
        if let wt = input.waterTempF {
            if !input.waterTempEstimated, wt < g.coldWaterF {
                hits.append(GateHit(reason: "Water too cold — \(Int(wt.rounded()))°F, no target species active",
                                    cap: Int(g.coldWaterCap)))
            } else if input.waterTempEstimated, wt < g.coldWaterEstimatedF {
                hits.append(GateHit(reason: "Water likely cold — ~\(Int(wt.rounded()))°F estimated, few fish shallow",
                                    cap: Int(g.coldWaterEstimatedCap)))
            }
        }
        // Storm gate requires corroboration — never trust the categorical code
        // alone (it over-reports storms on clear, dry nights).
        if g.stormWeatherCodes.contains(input.weatherCode),
           input.precipitationInchNow >= g.stormMinPrecipInch || input.cloudPct >= g.stormMinCloudPct {
            hits.append(GateHit(reason: "Thunderstorms",
                                cap: Int(g.stormCap)))
        }
        return hits
    }
}
