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
        if let last = lastRequests[appID], Date().timeIntervalSince(last) < 45 {
            throw LookupError.rateLimited
        }
        lastRequests[appID] = Date()

        let query = "[out:json][timeout:10];way(around:100,\(lat),\(lon))[highway][highway!~\"^(footway|cycleway|path|pedestrian|steps|bridleway|corridor|construction)$\"];out tags geom;"
        var url = URLComponents(string: "https://overpass-api.de/api/interpreter")!
        url.queryItems = [URLQueryItem(name: "data", value: query)]
        guard let endpoint = url.url else { throw LookupError.unavailable }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 14
        request.setValue("HTMLApp/1.6.31 (road tag lookup; user-consented)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              bytes.count <= 512_000,
              let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let ways = root["elements"] as? [[String: Any]] else {
            throw LookupError.unavailable
        }
        let match = ways.compactMap { way -> (Double, [String: Any])? in
            guard let tags = way["tags"] as? [String: String],
                  let geometry = way["geometry"] as? [[String: Double]],
                  !geometry.isEmpty else { return nil }
            // Center-of-way is unreliable for a road that stretches far beyond
            // the user's position; use the nearest geometry point instead.
            let meters = geometry.compactMap { point -> Double? in
                guard let wlat = point["lat"], let wlon = point["lon"] else { return nil }
                let dx = (wlon - longitude) * cos(latitude * .pi / 180) * 111_200
                let dy = (wlat - latitude) * 111_200
                return (dx * dx + dy * dy).squareRoot()
            }.min() ?? Double.infinity
            let raw = tags["maxspeed"] ?? ""
            return (meters, [
                "road": tags["name"] ?? tags["ref"] ?? "",
                "mappedMaxspeed": raw,
                "distanceMeters": meters
            ])
        }.min { $0.0 < $1.0 }
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
