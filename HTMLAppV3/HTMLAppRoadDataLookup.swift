import Foundation

/// User-consented third-party OSM road tags. This is not a certified traffic
/// or navigation speed-limit service. Never fabricate a statutory limit.
actor HTMLAppRoadDataLookup {
    static let shared = HTMLAppRoadDataLookup()
    private struct CacheEntry {
        let time: Date
        let result: [String: Any]
    }
    private var cache: [String: CacheEntry] = [:]
    private var lastRequests: [String: Date] = [:]

    func speedLimit(appID: String, latitude: Double, longitude: Double) async throws -> [String: Any] {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw LookupError.invalidCoordinates
        }
        // Round to ~100m cells to reduce raw precision and server load.
        let lat = (latitude * 1000).rounded() / 1000
        let lon = (longitude * 1000).rounded() / 1000
        let cell = String(format: "%.3f,%.3f", lat, lon)
        if let entry = cache[cell], Date().timeIntervalSince(entry.time) < 90 {
            return entry.result
        }
        if let last = lastRequests[appID], Date().timeIntervalSince(last) < 15 {
            // Frequent GPS fixes must not convert an otherwise healthy UI
            // into an immediate native-bridge error. Expose a retry interval.
            return [
                "status": "unknown",
                "provider": "OpenStreetMap Overpass",
                "source": "volunteer-mapped road tags",
                "authoritative": false,
                "reason": "throttled",
                "retryAfterSeconds": max(1, 15 - Int(Date().timeIntervalSince(last))),
                "warning": "Road lookup is cooling down; mapped speed limits are not guaranteed."
            ]
        }
        lastRequests[appID] = Date()

        let query = "[out:json][timeout:10];way(around:100,\(lat),\(lon))[highway][highway!~\"^(footway|cycleway|path|pedestrian|steps|bridleway|corridor|construction)$\"];out tags geom;"
        // Public Overpass instances are intermittently unavailable or
        // overloaded. Try a second independent service after a failure.
        // Native URLSession avoids WKWebView cross-origin POST limitations.
        let endpoints = [
            "https://overpass-api.de/api/interpreter",
            "https://overpass.kumi.systems/api/interpreter"
        ]
        var ways: [[String: Any]]?
        for service in endpoints {
            guard let endpoint = URL(string: service) else { continue }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 14
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("HTMLApp/1.6.31 (consented road-tag lookup)", forHTTPHeaderField: "User-Agent")
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "data", value: query)]
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
            do {
                let (bytes, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      bytes.count <= 1_500_000,
                      let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let elements = root["elements"] as? [[String: Any]] else { continue }
                ways = elements
                break
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        guard let ways else {
            // A failed provider request must not consume a full throttle period.
            lastRequests.removeValue(forKey: appID)
            throw LookupError.unavailable
        }
        let candidates = ways.compactMap { way -> (Double, [String: Any])? in
            guard let tags = way["tags"] as? [String: String],
                  let geometry = way["geometry"] as? [[String: Double]],
                  !geometry.isEmpty else { return nil }
            // Measure distance to road segments, not only their vertices.
            // Long straight roads otherwise appear far away despite passing
            // directly through the device's position.
            let vertices: [(Double, Double)] = geometry.compactMap { point in
                guard let wlat = point["lat"], let wlon = point["lon"] else { return nil }
                return ((wlon - longitude) * cos(latitude * .pi / 180) * 111_200,
                        (wlat - latitude) * 111_200)
            }
            let meters: Double = {
                guard let first = vertices.first else { return .infinity }
                guard vertices.count > 1 else { return hypot(first.0, first.1) }
                return zip(vertices, vertices.dropFirst()).map { a, b in
                    let dx = b.0 - a.0
                    let dy = b.1 - a.1
                    let squared = dx * dx + dy * dy
                    let fraction = squared > 0 ? max(0, min(1, -(a.0 * dx + a.1 * dy) / squared)) : 0
                    return hypot(a.0 + fraction * dx, a.1 + fraction * dy)
                }.min() ?? .infinity
            }()
            let raw = tags["maxspeed"] ?? ""
            return (meters, [
                "road": tags["name"] ?? tags["ref"] ?? "",
                "mappedMaxspeed": raw,
                "distanceMeters": meters
            ])
        }
        // Prefer an explicitly tagged and sufficiently close road over a
        // closer unnamed/untagged foot-adjacent carriageway. Never match a
        // distant road solely because it has a speed tag.
        let match = candidates.filter {
            $0.0 <= 35 && !($0.1["mappedMaxspeed"] as? String ?? "").isEmpty
        }.min { $0.0 < $1.0 } ?? candidates.min { $0.0 < $1.0 }
        var result: [String: Any] = [
            "status": "unknown",
            "provider": "OpenStreetMap Overpass",
            "source": "volunteer-mapped road tags",
            "authoritative": false,
            "warning": "Mapped tags may be absent, incomplete, outdated or from an adjacent road; never rely on this for legal compliance.",
            "road": "",
            "mappedMaxspeed": ""
        ]
        if let match, match.0 <= 90 {
            result.merge(match.1) { _, new in new }
            let raw = (match.1["mappedMaxspeed"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            // Only expose a numeric value when an explicit supported unit is
            // present. No inference of national default units.
            let parts = raw.split(separator: " ")
            if parts.count == 2, let limit = Double(parts[0]), limit > 0, limit <= 200,
               ["mph", "km/h"].contains(String(parts[1])) {
                result["status"] = "mapped"
                result["speedLimit"] = limit
                result["unit"] = String(parts[1])
            }
        }
        cache[cell] = CacheEntry(time: Date(), result: result)
        if cache.count > 120 { cache.removeAll() }
        return result
    }

    enum LookupError: LocalizedError {
        case invalidCoordinates, rateLimited, unavailable
        var errorDescription: String? {
            switch self {
            case .invalidCoordinates: return "Invalid latitude or longitude."
            case .rateLimited: return "Road lookup throttled to protect public data servers. Retry later."
            case .unavailable: return "OpenStreetMap road data unavailable or rate limited."
            }
        }
    }
}
