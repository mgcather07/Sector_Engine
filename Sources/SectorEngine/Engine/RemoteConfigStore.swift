//
//  RemoteConfigStore.swift
//  SectorEngine
//
//  Phase 6 Stage 4: drive the engine's tuning from Firebase Remote Config, so
//  scoring can change WITHOUT a redeploy. Reads the `conditions_config` parameter
//  (a JSON ConditionsConfigOverrides blob), applies it onto ConditionsConfig.default,
//  and caches the result for a short TTL. Both the gauge and the forecast ask this
//  store for the current config.
//
//  There is no Firebase Admin SDK for Swift, so this uses the Remote Config REST
//  API, authenticated by the Cloud Run service account via the GCP metadata server.
//  Every failure path falls back to the last good config (or the compiled default),
//  so a Remote Config outage — or running locally, off Cloud Run — is harmless.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor RemoteConfigStore {
    static let shared = RemoteConfigStore()

    private var cached: ConditionsConfig = .default
    private var fetchedAt: Date?
    private let ttl: TimeInterval = 10 * 60
    private var inFlight: Task<ConditionsConfig, Never>?

    /// Firebase project id (same as the GCP project). Overridable via env for staging.
    private let projectId = ProcessInfo.processInfo.environment["GCP_PROJECT"] ?? "sector-9393c"

    /// The current tuned config. Served from cache within the TTL; refreshed on a
    /// stale read (concurrent stale reads coalesce onto one fetch). Never throws.
    func current() async -> ConditionsConfig {
        if let at = fetchedAt, Date().timeIntervalSince(at) < ttl { return cached }
        if let task = inFlight { return await task.value }
        let task = Task { await fetchAndApply() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func fetchAndApply() async -> ConditionsConfig {
        // Mark the attempt time either way so a persistent failure backs off to the
        // TTL instead of hammering the metadata server on every request.
        defer { fetchedAt = Date() }
        guard let overrides = await fetchOverrides() else { return cached }
        cached = overrides.apply(to: .default)
        return cached
    }

    private func fetchOverrides() async -> ConditionsConfigOverrides? {
        guard let token = await accessToken(),
              let url = URL(string: "https://firebaseremoteconfig.googleapis.com/v1/projects/\(projectId)/remoteConfig")
        else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            // template → parameters → conditions_config → defaultValue → value (a JSON string)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let params = root["parameters"] as? [String: Any],
                  let param = params["conditions_config"] as? [String: Any],
                  let defaultValue = param["defaultValue"] as? [String: Any],
                  let value = defaultValue["value"] as? String,
                  let valueData = value.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(ConditionsConfigOverrides.self, from: valueData)
        } catch {
            return nil
        }
    }

    /// OAuth access token for the Cloud Run service account, from the metadata server.
    /// Returns nil off Cloud Run (local dev), so `current()` just serves defaults.
    private func accessToken() async -> String? {
        guard let url = URL(string: "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token")
        else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.setValue("Google", forHTTPHeaderField: "Metadata-Flavor")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = obj["access_token"] as? String else { return nil }
            return token
        } catch {
            return nil
        }
    }
}
