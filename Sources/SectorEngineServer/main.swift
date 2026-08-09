//
//  SectorEngineServer
//
//  Thin HTTP wrapper around SectorEngineAPI. GET /conditions?lat=&lon= → JSON.
//  This is what Cloud Run will run; for Phase 0 it runs on localhost so iOS can
//  A/B its numbers against the app's local engine.
//

import Foundation
import Hummingbird
import SectorEngine

let router = Router()

router.get("health") { _, _ in "ok" }

router.get("conditions") { request, _ -> Response in
    guard let lat = request.uri.queryParameters.get("lat").flatMap({ Double(String($0)) }),
          let lon = request.uri.queryParameters.get("lon").flatMap({ Double(String($0)) }) else {
        return Response(status: .badRequest)
    }

    guard let payload = await SectorEngineAPI.conditions(lat: lat, lon: lon) else {
        return Response(status: .serviceUnavailable)   // no live data to score
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = (try? encoder.encode(payload)) ?? Data()

    var buffer = ByteBuffer()
    buffer.writeBytes(data)
    return Response(
        status: .ok,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: buffer))
}

// Cloud Run injects PORT and expects the server to bind 0.0.0.0 (all interfaces).
// Locally, without PORT set, that's still reachable as localhost:8080 for the A/B.
let port = ProcessInfo.processInfo.environment["PORT"].flatMap(Int.init) ?? 8080
let app = Application(
    router: router,
    configuration: .init(address: .hostname("0.0.0.0", port: port)))

try await app.runService()
